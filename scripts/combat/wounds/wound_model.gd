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
## NPA clears the airway so SpO2 recovers, and blood comes back only through an IV or IO
## line with a bag of saline or blood running.
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

## --- Breathing: SpO2 (hidden from players; a medic reads it on a pulse oximeter) ---
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
## lost past EFFECTS_FROM_LOST (less blood to carry oxygen: 90% at 40% lost), per share of
## lung efficiency lost (both lungs averaged: lung_efficiency), and per dose of morphine in
## the blood past MORPHINE_DEPRESSION_LEVEL (slowed breathing). An obstructed airway heads
## for SPO2_OBSTRUCTED; cardiac arrest for 0.
const SPO2_BLOOD_DROP := 32.0
const SPO2_LUNG_DROP := 30.0
const SPO2_PER_MORPHINE := 12.0

## --- Breathing (design doc "Chest"; proposed values) ---
## Each lung has an efficiency from 0 to 1: 1 less its collapse (pneumothorax) and the blood
## in it (hemothorax). An unsealed chest wound lets its lung collapse to OPEN_CHEST_COLLAPSE
## (at COLLAPSE_PER_S); a tension pneumothorax collapses it fully and pushes on the other lung
## (TENSION_SHIFT off its efficiency) until a decompression needle lets the air out. Once
## sealed, a lung re-expands over REEXPAND_S. Blood from a bleeding chest wound fills its
## side's lung: HEMOTHORAX_L fills it (efficiency 0), at most FLUID_MAX, and stays there (no
## chest drain in the field).
const LUNGS: Array[StringName] = [&"lung_l", &"lung_r"]
const OPEN_CHEST_COLLAPSE := 0.4
const COLLAPSE_PER_S := 1.0 / 30.0
const REEXPAND_S := 120.0
const TENSION_SHIFT := 0.4
const HEMOTHORAX_L := 1.5
const FLUID_MAX := 0.8
## Breaths per minute: RESP_NORMAL, faster with lost lung efficiency and blood loss (shock),
## slower past MORPHINE_DEPRESSION_LEVEL; none in arrest. Hidden like SpO2: players see
## "Breathing fast" over RESP_FAST and "Breathing slow" under RESP_SLOW.
const RESP_NORMAL := 16.0
const RESP_PER_LUNG := 24.0
const RESP_PER_SHOCK := 10.0
const RESP_PER_MORPHINE := 6.0
const RESP_MIN := 4.0
const RESP_FAST := 24.0
const RESP_SLOW := 10.0
## The decompression needle's own pain (proposed).
const NEEDLE_PAIN := 0.05
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
const IO_KIT := &"io_kit"
const PRESSURE_BAG := &"pressure_bag"
const NEEDLE := &"decompression_needle"
## IV catheters by item id: their gauge (design doc, "IV gauge sets the flow").
const IV_GAUGES := {&"iv_10": 10, &"iv_12": 12, &"iv_14": 14, &"iv_16": 16, &"iv_18": 18, &"iv_20": 20}
## Fluid bags by item id: mL. Saline and blood work the same (design doc).
const FLUID_BAGS := {&"saline_250": 250, &"saline_500": 500, &"saline_1000": 1000,
	&"blood_250": 250, &"blood_500": 500, &"blood_1000": 1000}

## Blood comes back only through IV or IO access plus a bag (design doc; proposed values).
## One line at a time, one bag running on it at a time. A bag takes BAG_BASE_S through an
## 18 gauge (the middle of the design doc's ranges); a gauge flows GAUGE_FLOW times that and
## adds GAUGE_PAIN when placed. IO flows like an 18 gauge, or 2x under a pressure bag.
const BAG_BASE_S := {250: 165.0, 500: 270.0, 1000: 450.0}
const GAUGE_FLOW := {10: 5.0, 12: 4.0, 14: 3.0, 16: 2.0, 18: 1.0, 20: 0.6}
const GAUGE_PAIN := {10: 0.2, 12: 0.15, 14: 0.12, 16: 0.08, 18: 0.05, 20: 0.02}
const IO_PAIN := 0.1
const PRESSURE_FLOW := 2.0
## Veins collapse from this share lost (design doc): an IV then runs at COLLAPSED_FLOW of its
## gauge rate, or COLLAPSED_PRESSURE_FLOW under a pressure bag.
const VEIN_COLLAPSE_LOST := 0.37
const COLLAPSED_FLOW := 0.5
const COLLAPSED_PRESSURE_FLOW := 1.25
## An IV in shock: from IV_HARD_FROM_LOST lost it takes longer to place (up to
## IV_SHOCK_TIME_MULT times) and misses more often (up to IV_FAIL_MAX), both reached at
## ARREST_LOST. A missed IV uses the catheter up. IO always goes in.
const IV_HARD_FROM_LOST := 0.25
const IV_SHOCK_TIME_MULT := 2.0
const IV_FAIL_MAX := 0.6
## Access and fluids are asked for (care_tasks) from this share lost.
const FLUIDS_FROM_LOST := 0.15
## Where lines go: an IV in a forearm (the right one if the left arm has a tourniquet), an
## IO in the sternum.
const IV_PART := &"forearm_l"
const IV_PART_OTHER := &"forearm_r"
const IO_PART := &"chest"
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

## --- Heart rate and the other three drugs (design doc "Drugs", "Defibrillator"; proposed) ---
## Heart rate (bpm) heads for a target at HR_CHANGE_PER_S: HR_REST, faster with blood loss
## (shock) and pain, slower on morphine and low SpO2, and falling toward HR_DEEP_SHOCK as
## loss nears ARREST_LOST; 0 in arrest. Each drug in the blood moves it by its HR_PER_DOSE.
## Racing over HR_RACING or slower than HR_SLOW for HR_DANGER_S stops the heart. A medic
## reads it as a pulse (no rhythms).
const HR_REST := 75.0
const HR_PER_SHOCK := 60.0
const HR_PER_PAIN := 25.0
const HR_PER_MORPHINE := -12.0
const HR_PER_LOW_SPO2 := -0.5        # per SpO2 point under HR_SPO2_FROM
const HR_SPO2_FROM := 80.0
const HR_DEEP_SHOCK := 40.0
const HR_DEEP_SHOCK_FROM := 0.40     # lost
const HR_CHANGE_PER_S := 8.0
const HR_RACING := 150.0
const HR_SLOW := 45.0
const HR_DEADLY_FAST := 200.0
const HR_DEADLY_SLOW := 35.0
const HR_DANGER_S := 60.0
## Drugs other than morphine, by item id: one dose goes in over absorb_s, the level halves
## every half_life_s, and each dose in the blood moves the heart rate by hr (bpm).
const EPINEPHRINE := &"epinephrine"
const ATROPINE := &"atropine"
const ADENOSINE := &"adenosine"
const DRUGS := {
	&"epinephrine": {"absorb_s": 10.0, "half_life_s": 120.0, "hr": 30.0},
	&"atropine": {"absorb_s": 10.0, "half_life_s": 600.0, "hr": 30.0},
	&"adenosine": {"absorb_s": 2.0, "half_life_s": 120.0, "hr": -40.0},
}
## Epinephrine's wake-up roll (decided; build plan: a chance to come round sooner, never a
## revive): given to someone out with no cause left but a concussion knockout (or already
## coming round), EPI_WAKE_CHANCE that the knockout clears and they come round in EPI_WAKE_S.
const EPI_WAKE_CHANCE := 0.5
const EPI_WAKE_S := 2.0
## Restarting a heart in arrest: CPR (a cycle of the "cpr" action) and the defibrillator do
## nothing until blood is back to RESTART_MIN_BLOOD (design doc: above 60%). Then each CPR
## cycle restarts it with CPR_RESTART_CHANCE and each shock with DEFIB_RESTART_CHANCE, plus
## EPI_RESTART_BONUS per dose of epinephrine in the blood (up to one dose). A heart that
## restarts beats at HR_RESTART.
const CPR := &"cpr"
const DEFIBRILLATOR := &"defibrillator"
const RESTART_MIN_BLOOD := 0.6
const CPR_RESTART_CHANCE := 0.08
const DEFIB_RESTART_CHANCE := 0.35
const EPI_RESTART_BONUS := 0.15
const HR_RESTART := 60.0
## Airway (proposed): an unconscious casualty without an NPA obstructs with this chance per
## minute; SpO2 then falls toward SPO2_OBSTRUCTED until an NPA goes in. Someone out for
## less than AIRWAY_SELF_CLEAR_S (a short knockout, a brief faint from pain) stirs and clears
## it themselves once the obstruction is all that keeps them out; out longer, only an NPA does.
const AIRWAY_BLOCK_PER_MIN := 0.1
const AIRWAY_SELF_CLEAR_S := 45.0
## Bleeding the everyday kit (IFAK) can control. Internal (torso) bleeding only stops under a
## surgery kit's clamp (players and medics), so it stays out of injury() (what AI treats
## itself for).
const FIXABLE_BLEEDS: Array[String] = ["arterial", "junctional", "venous", "muscle", "graze"]
const BANDAGED_KINDS: Array[String] = ["venous", "muscle", "graze"]
## Countdowns that clients run down between updates (to_net "t").
const TIMERS: Array[String] = ["arrest_left", "concussion_left", "knockout_left", "winded_left", "stagger_left",
	"treating_left", "wake_left", "deaf_left"]

## --- Surgery kit (design doc "Surgery kit"; proposed values) ---
## One use of a kit is a SURGICAL_CLAMP (kits hold 2, 3 or 5): about 20 s, players and medics
## only. It clamps an internal (torso) artery or vein, or a junctional or arterial bleed, or
## closes a chest wound in place of a seal. A closed chest wound reopens with CHEST_REOPEN_CHANCE
## each time the casualty exerts themselves (sprints, jumps, moves under an extreme load:
## exert), which brings back the open wound and its tension risk.
const SURGICAL_CLAMP := &"surgical_clamp"
const CLAMPED_KINDS: Array[String] = ["internal", "junctional", "arterial"]
const CHEST_REOPEN_CHANCE := 0.1

## --- Other damage (design doc "Other damage"; proposed values) ---
## Overpressure from a blast within BLAST_RADIUS (doubled indoors): deafness for 20 to 60 s by
## closeness, a concussion check (BLAST_CONCUSSION_CHANCE at the centre) and a small chance of
## blast lung, which slowly fills both lungs (BLAST_LUNG_FLUID_PER_S up to BLAST_LUNG_MAX) and
## has no field fix. Close blasts (within BURN_RADIUS) also burn.
const BLAST_RADIUS := 5.0
const BLAST_DEAF_S := Vector2(20.0, 60.0)
const BLAST_CONCUSSION_CHANCE := 0.5
const BLAST_LUNG_CHANCE := 0.15
const BLAST_LUNG_FLUID_PER_S := 0.002
const BLAST_LUNG_MAX := 0.5
const BLAST_IMPACT := 0.25
const BURN_RADIUS := 2.0
const BLAST_BURN := Vector2(0.05, 0.25)    # share of the body burned at the edge / the centre
## Falls: nothing under FALL_SAFE_M; to FALL_HARD_M, leg pain and a fracture chance rising
## from 30% to 70%; above FALL_FATAL_M likely fatal (the chance rises to FALL_FATAL_CHANCE
## between FALL_HARD_M and FALL_FATAL_M).
const FALL_SAFE_M := 3.0
const FALL_HARD_M := 6.0
const FALL_FATAL_M := 10.0
const FALL_FRACTURE_CHANCE := Vector2(0.3, 0.7)
const FALL_PAIN := Vector2(0.2, 0.5)
const FALL_FATAL_CHANCE := 0.9
## Burns, as a share of the body: pain BURN_PAIN per share (eased BURN_DRESSING_PAIN per
## dressing, up to the burned share / BURN_PER_DRESSING dressings); over BURN_FLUID_FROM, fluid
## loss like bleeding at BURN_FLUID_RATE L/min per share past it. IV fluids replace it.
const BURN_DRESSING := &"burn_dressing"
const BURN_PAIN := 1.2
const BURN_DRESSING_PAIN := 0.15
const BURN_PER_DRESSING := 0.1
const BURN_FLUID_FROM := 0.2
const BURN_FLUID_RATE := 0.5
## Hypothermia: HYPOTHERMIA_LOST or more lost and lying still for HYPOTHERMIA_STILL_S: bleeding
## HYPOTHERMIA_BLEED times faster, until a blanket goes on.
const BLANKET := &"hypothermia_blanket"
const HYPOTHERMIA_LOST := 0.3
const HYPOTHERMIA_STILL_S := 300.0
const HYPOTHERMIA_BLEED := 1.25
## Indoor gunfire: each shot heard indoors close by adds 1 to a noise level that fades
## NOISE_FADE_PER_S; past NOISE_DEAF, muffled hearing for NOISE_DEAF_S. Flashbangs deafen for
## 3 to 6 s. Electronic ear protection prevents both and halves blast deafness.
const NOISE_FADE_PER_S := 1.0
const NOISE_DEAF := 10.0
const NOISE_DEAF_S := 30.0

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
## Dice for the treatment rules (airway, a missed IV), apart from rng so the wound dice repeat.
var care_rng := RandomNumberGenerator.new()
## The IV or IO line: {} for none, else "kind" ("iv" or "io"), "gauge" (an IV's; 0 for IO),
## "part" and "pressure" (a pressure bag is on it).
var access: Dictionary = {}
## The bag running on the line: {} for none, else "item", "ml" (its size) and "left" (mL).
var infusion: Dictionary = {}
## Host: what the last apply_item has to tell the treater ("Missed the vein"), or "".
var care_note := ""
## Per lung (LUNGS): how far it has collapsed and how full of blood it is, 0 to 1.
var lung_collapse := {&"lung_l": 0.0, &"lung_r": 0.0}
var lung_fluid := {&"lung_l": 0.0, &"lung_r": 0.0}

var _time := 0.0
var _last_concussion := -INF
var _heart_arrest_in := -1.0
var _spell_wake_s := 0.0        # how long the worst cause of this spell out takes to wake from
var _low_spo2_s := 0.0          # time spent under SPO2_ARREST
var _out_s := 0.0               # how long this spell out has lasted (host only)
var _pain_over_s := 0.0         # how long pain has stayed at or over the knockout threshold
## Beats per minute (see HR_REST).
var heart_rate := HR_REST
## Other drugs (DRUGS ids): in the blood and still going in, in doses.
var drug_level := {&"epinephrine": 0.0, &"atropine": 0.0, &"adenosine": 0.0}
var drug_depot := {&"epinephrine": 0.0, &"atropine": 0.0, &"adenosine": 0.0}
var _hr_danger_s := 0.0         # time spent racing or too slow (host only)
## Hearing muffled (seconds left), and the indoor gunfire noise level building toward it.
var deaf_left := 0.0
var noise := 0.0
## Blast lung: both lungs slowly fill (see BLAST_LUNG_CHANCE).
var blast_lung := false
## Share of the body burned (0 to 1), and burn dressings on.
var burn := 0.0
var burn_dressings := 0
## Seconds lying still (host: Vitals reports movement), and a hypothermia blanket is on.
var still_s := 0.0
var blanket := false


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


## Blood actually leaving the body now, in L/min: the wounds by what the heart pushes out
## (faster when hypothermic), plus fluid lost to burns.
func bleed_rate() -> float:
	return wound_bleed_rate() * cardiac_output() * (HYPOTHERMIA_BLEED if hypothermic() else 1.0) + burn_fluid_rate()


## Fluid lost to burns over BURN_FLUID_FROM of the body, in L/min.
func burn_fluid_rate() -> float:
	return maxf(burn - BURN_FLUID_FROM, 0.0) * BURN_FLUID_RATE if not dead else 0.0


## Pain from burns still undressed.
func burn_pain() -> float:
	return maxf(BURN_PAIN * burn - BURN_DRESSING_PAIN * burn_dressings, 0.0)


## Burn dressings that would still help (one per BURN_PER_DRESSING of the body burned).
func burn_dressings_needed() -> int:
	return maxi(ceili(burn / BURN_PER_DRESSING - 0.001) - burn_dressings, 0)


## Lost HYPOTHERMIA_LOST or more and lying still for HYPOTHERMIA_STILL_S, with no blanket.
func hypothermic() -> bool:
	return not blanket and not dead and lost() >= HYPOTHERMIA_LOST and still_s >= HYPOTHERMIA_STILL_S


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
	target -= SPO2_LUNG_DROP * (1.0 - lung_efficiency())
	target -= SPO2_PER_MORPHINE * maxf(morphine_level - MORPHINE_DEPRESSION_LEVEL, 0.0)
	return clampf(target, 0.0, SPO2_NORMAL)


## A tension pneumothorax runs on `lung`'s side (chest wounds are named for their lung).
func _tension_on(lung: StringName) -> bool:
	return wounds.any(func(w: Dictionary) -> bool: return w.kind == "chest" and w.name == lung and w.get("tension", false))


## One lung's efficiency, 0 to 1: less what's collapsed and the blood in it, and less
## TENSION_SHIFT while the other side is under tension.
func lung_efficiency_of(lung: StringName) -> float:
	var other: StringName = LUNGS[1] if lung == LUNGS[0] else LUNGS[0]
	var eff := 1.0 - float(lung_collapse[lung]) - float(lung_fluid[lung])
	if _tension_on(other):
		eff -= TENSION_SHIFT
	return clampf(eff, 0.0, 1.0)


## Both lungs' efficiency averaged, 0 to 1 (1 healthy).
func lung_efficiency() -> float:
	return (lung_efficiency_of(LUNGS[0]) + lung_efficiency_of(LUNGS[1])) * 0.5


## Breaths per minute now (hidden; see RESP_NORMAL).
func respiratory_rate() -> float:
	if arrest or dead:
		return 0.0
	var rate := RESP_NORMAL + RESP_PER_LUNG * (1.0 - lung_efficiency()) + RESP_PER_SHOCK * shock()
	rate -= RESP_PER_MORPHINE * maxf(morphine_level - MORPHINE_DEPRESSION_LEVEL, 0.0)
	return maxf(rate, RESP_MIN)


## A tension pneumothorax is running on either side.
func has_tension() -> bool:
	return wounds.any(func(w: Dictionary) -> bool: return w.kind == "chest" and w.get("tension", false))


## The heart rate the body heads for now (see HR_REST); 0 in arrest.
func heart_rate_target() -> float:
	if arrest or dead:
		return 0.0
	var target := HR_REST + HR_PER_SHOCK * shock() + HR_PER_PAIN * pain() + HR_PER_MORPHINE * morphine_level
	target += HR_PER_LOW_SPO2 * maxf(HR_SPO2_FROM - spo2, 0.0)
	var deep := clampf((lost() - HR_DEEP_SHOCK_FROM) / (ARREST_LOST - HR_DEEP_SHOCK_FROM), 0.0, 1.0)
	target = lerpf(target, HR_DEEP_SHOCK, deep)
	for id: StringName in DRUGS:
		target += float(DRUGS[id].hr) * float(drug_level[id])
	return clampf(target, 20.0, 220.0)


## A drug (DRUGS id) in the blood plus what's still going in, in doses.
func drug_total(id: StringName) -> float:
	return float(drug_level[id]) + float(drug_depot[id])


## Blood is back far enough for CPR or the defibrillator to restart the heart.
func can_restart() -> bool:
	return blood >= RESTART_MIN_BLOOD - 0.0001


## Chance one CPR cycle (`item` CPR) or one shock (DEFIBRILLATOR) restarts the heart now.
func restart_chance(item: StringName) -> float:
	if not arrest or not can_restart():
		return 0.0
	var base := DEFIB_RESTART_CHANCE if item == DEFIBRILLATOR else CPR_RESTART_CHANCE
	return base + EPI_RESTART_BONUS * minf(float(drug_level[EPINEPHRINE]), 1.0)


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
	if spo2 < SPO2_LABOURED or lung_efficiency() < 0.85:
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


## Pain morphine can take off: wound, impact and undressed burn pain, not the floors that
## fractures keep (or what tourniquets add).
func reducible_pain() -> float:
	return clampf(pain_wounds + impact + burn_pain(), 0.0, 1.0)


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


# --- Lines and fluids -------------------------------------------------------------------

func veins_collapsed() -> bool:
	return lost() >= VEIN_COLLAPSE_LOST


## The line's flow as a multiple of the 18 gauge rate (0 without a line): its gauge, then a
## pressure bag (2x) or collapsed veins (an IV: half, or 1.25x under a pressure bag).
func flow_mult() -> float:
	if access.is_empty():
		return 0.0
	var pressure: bool = access.pressure
	if access.kind == "io":
		return PRESSURE_FLOW if pressure else 1.0
	var gauge := float(GAUGE_FLOW.get(int(access.gauge), 1.0))
	if veins_collapsed():
		return gauge * (COLLAPSED_PRESSURE_FLOW if pressure else COLLAPSED_FLOW)
	return gauge * (PRESSURE_FLOW if pressure else 1.0)


## mL per second going in now (0 with no bag running).
func infusion_rate() -> float:
	if infusion.is_empty():
		return 0.0
	var ml := int(infusion.ml)
	return float(ml) / float(BAG_BASE_S.get(ml, 270.0)) * flow_mult()


## How hard an IV is to place now: 0 up to IV_HARD_FROM_LOST lost, 1 at ARREST_LOST.
func iv_difficulty() -> float:
	return clampf((lost() - IV_HARD_FROM_LOST) / (ARREST_LOST - IV_HARD_FROM_LOST), 0.0, 1.0)


## Placement time multiplier for `item` on this body (an IV takes longer in shock).
func treat_time_mult(item: StringName) -> float:
	return 1.0 + (IV_SHOCK_TIME_MULT - 1.0) * iv_difficulty() if IV_GAUGES.has(item) else 1.0


## The forearm an IV goes in: the left, unless a tourniquet is on that arm.
func iv_part() -> StringName:
	return IV_PART_OTHER if tourniquets.has(&"upper_arm_l") or tourniquets.has(IV_PART) else IV_PART


## Items that would give this body a line, best pick first: in deep shock (veins collapsed
## or arrest) IO, then the big bores; with time, the common 18 gauge first.
func access_options() -> Array[StringName]:
	var out: Array[StringName] = []
	if veins_collapsed() or arrest:
		out.assign([IO_KIT, &"iv_14", &"iv_12", &"iv_10", &"iv_16", &"iv_18", &"iv_20"])
	else:
		out.assign([&"iv_18", &"iv_16", &"iv_14", &"iv_20", &"iv_12", &"iv_10", IO_KIT])
	return out


## Bags, best pick first: the size closest to the blood still missing, blood before saline.
func bag_options() -> Array[StringName]:
	var need := lost() * BLOOD_L * 1000.0
	var sizes := [1000, 500, 250] if need >= 900.0 else ([500, 1000, 250] if need >= 400.0 else [250, 500, 1000])
	var out: Array[StringName] = []
	for ml: int in sizes:
		out.append(StringName("blood_%d" % ml))
		out.append(StringName("saline_%d" % ml))
	return out


# --- Treatment ------------------------------------------------------------------------

## What still needs doing, most urgent first, in the casualty-care order: massive bleeding
## (a tourniquet per limb segment, gauze for junctional bleeds), airway (an NPA for an
## unconscious casualty), chest (a seal per open chest wound), other bleeding (bandages),
## circulation (from FLUIDS_FROM_LOST lost: IV or IO access, then a bag; a pressure bag once
## veins collapse), fractures (splints), pain (morphine, also for a cracked rib). One
## {"part", "kind", "item"} per task; where several items do the job ("access", "fluids")
## "items" lists them all, best pick first, and "item" is the first. Only items that would
## help: wounds already handled (treated, under a good
## tourniquet) are skipped, internal bleeding waits for surgery, a tension pneumothorax
## asks for the needle (kind "tension"), and morphine only for pain still left once what's given has worked, while the
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
			tasks.append(_task(w.part, w.kind, &"", _options(HEMOSTATIC_GAUZE, SURGICAL_CLAMP)))
		elif w.kind == "internal":
			tasks.append(_task(w.part, "internal", SURGICAL_CLAMP))
	if unconscious and not arrest and not npa:
		tasks.append(_task(&"head", "airway", NPA))
	if has_tension():
		tasks.append(_task(&"chest", "tension", NEEDLE))
	for w: Dictionary in by_rate:
		if w.kind == "chest" and not w.treated:
			tasks.append(_task(w.part, "chest", &"", _options(CHEST_SEAL, SURGICAL_CLAMP)))
	for w: Dictionary in by_rate:
		if String(w.kind) in BANDAGED_KINDS and rate_now(w) > 0.0:
			tasks.append(_task(w.part, w.kind, PRESSURE_BANDAGE))
	if access.is_empty():
		if lost() >= FLUIDS_FROM_LOST:
			tasks.append(_task(iv_part(), "access", &"", access_options()))
	else:
		if infusion.is_empty() and lost() >= FLUIDS_FROM_LOST:
			tasks.append(_task(access.part, "fluids", &"", bag_options()))
		if veins_collapsed() and not access.pressure:
			tasks.append(_task(access.part, "pressure", PRESSURE_BAG))
	if not blanket and lost() >= HYPOTHERMIA_LOST and (unconscious or still_s >= HYPOTHERMIA_STILL_S * 0.5):
		tasks.append(_task(&"torso", "hypothermia", BLANKET))
	if arrest and can_restart():  # blood back: epinephrine, then shocks and CPR until it beats
		if drug_total(EPINEPHRINE) < 0.5:
			tasks.append(_task(&"torso", "epinephrine", EPINEPHRINE))
		tasks.append(_task(&"chest", "defib", DEFIBRILLATOR))
		tasks.append(_task(&"chest", "cpr", CPR))
	elif not arrest and not dead:
		if heart_rate > HR_RACING and drug_total(ADENOSINE) < 0.5:
			tasks.append(_task(&"torso", "racing", ADENOSINE))
		elif heart_rate < HR_SLOW and drug_total(ATROPINE) < 0.5:
			tasks.append(_task(&"torso", "slow_heart", ATROPINE))
		if unconscious and _epi_can_wake() and drug_total(EPINEPHRINE) < 0.5:
			tasks.append(_task(&"torso", "wake", EPINEPHRINE))
	for w: Dictionary in by_rate:
		if w.kind == "fracture" and not w.treated:
			tasks.append(_task(w.part, "fracture", SPLINT))
	if burn_dressings_needed() > 0:
		tasks.append(_task(&"torso", "burn", BURN_DRESSING))
	if not arrest and morphine_room() and (pain_to_ease() >= MORPHINE_FROM_PAIN or _untreated_rib()):
		tasks.append(_task(&"torso", "pain", MORPHINE))
	return tasks


## Why one `item` on `part` wouldn't help right now, or "" if it would.
func treatment_problem(item: StringName, part: StringName) -> String:
	if dead:
		return "Too late"
	if item == IO_KIT or IV_GAUGES.has(item):
		return "Already has a line in" if not access.is_empty() else ""
	if FLUID_BAGS.has(item):
		if access.is_empty():
			return "Needs IV or IO access first"
		if not infusion.is_empty():
			return "A bag is already running"
		return "No blood to replace" if lost() < 0.01 else ""
	if item == PRESSURE_BAG:
		if access.is_empty():
			return "Needs IV or IO access first"
		return "Already under a pressure bag" if access.pressure else ""
	if item == NEEDLE:
		return "" if has_tension() else "No tension pneumothorax"
	if item == CPR or item == DEFIBRILLATOR:
		if not arrest:
			return "The heart is beating"
		return "" if can_restart() else "Get blood back in first: an empty heart can't restart"
	if DRUGS.has(item):
		return ""
	if item == SURGICAL_CLAMP:
		return "" if not _clamp_target(part).is_empty() else "Nothing to clamp or close there"
	if item == BURN_DRESSING:
		return "" if burn_dressings_needed() > 0 else "No burns left to dress"
	if item == BLANKET:
		return "Already wrapped in a blanket" if blanket else ""
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
## tourniquet placed in a hurry or under fire. Returns whether the item was used: a missed
## IV is (care_note says so). IV and IO pick their own place (iv_part, IO_PART).
func apply_item(item: StringName, part: StringName, rushed := false) -> bool:
	care_note = ""
	if treatment_problem(item, part) != "":
		return false
	if IV_GAUGES.has(item):
		var gauge := int(IV_GAUGES[item])
		pain_wounds = minf(pain_wounds + float(GAUGE_PAIN[gauge]), 1.0)
		if care_rng.randf() < IV_FAIL_MAX * iv_difficulty():
			care_note = "Missed the vein"
		else:
			access = {"kind": "iv", "gauge": gauge, "part": iv_part(), "pressure": false}
		update_state(0.0)
		return true
	match item:
		IO_KIT:
			pain_wounds = minf(pain_wounds + IO_PAIN, 1.0)
			access = {"kind": "io", "gauge": 0, "part": IO_PART, "pressure": false}
		PRESSURE_BAG:
			access.pressure = true
		SURGICAL_CLAMP:  # hemostats on the worst bleed there, or the chest wound closed
			var w := _clamp_target(part)
			w.treated = true
			if w.kind == "chest":
				w.closed = true
				w.tension_in = -1.0
			else:
				w.clamped = true
		BURN_DRESSING:
			burn_dressings += 1
		BLANKET:
			blanket = true
		CPR, DEFIBRILLATOR:  # a cycle or a shock: a chance the heart starts again
			if care_rng.randf() < restart_chance(item):
				_restart_heart()
				care_note = "Pulse back"
			else:
				care_note = "Still no pulse"
		_ when DRUGS.has(item):
			drug_depot[item] = float(drug_depot[item]) + 1.0
			if item == EPINEPHRINE and unconscious and not arrest and _epi_can_wake():
				if care_rng.randf() < EPI_WAKE_CHANCE:
					knockout_left = 0.0
					_spell_wake_s = EPI_WAKE_S
					wake_left = minf(wake_left, EPI_WAKE_S) if wake_left > 0.0 else 0.0
					care_note = "Coming round"
				else:
					care_note = "No response"
		NEEDLE:  # lets the air out: the tension and the arrest it was heading for stop
			pain_wounds = minf(pain_wounds + NEEDLE_PAIN, 1.0)
			for w in wounds:
				if w.kind == "chest" and w.get("tension", false):
					w.tension = false
					w.arrest_in = -1.0
					var lung := _lung_of(w)
					lung_collapse[lung] = minf(float(lung_collapse[lung]), OPEN_CHEST_COLLAPSE)
		_ when FLUID_BAGS.has(item):
			var ml := int(FLUID_BAGS[item])
			infusion = {"item": item, "ml": ml, "left": float(ml)}
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


## What one surgical clamp on `part` would do: the worst bleeding internal, junctional or
## arterial wound there, else an open chest wound to close; {} for nothing.
func _clamp_target(part: StringName) -> Dictionary:
	var best := {}
	for w in wounds:
		if w.part == part and String(w.kind) in CLAMPED_KINDS and is_bleeding(w) \
				and (best.is_empty() or float(w.rate) > float(best.rate)):
			best = w
	if not best.is_empty():
		return best
	for w in wounds:
		if w.part == part and w.kind == "chest" and not w.treated:
			return w
	return {}


## Host only. The casualty exerted themselves (sprinted, jumped, moved under an extreme
## load): each chest wound closed with a clamp reopens with CHEST_REOPEN_CHANCE, open again
## with its tension risk. Returns how many reopened.
func exert() -> int:
	var reopened := 0
	for w in wounds:
		if w.kind == "chest" and w.get("closed", false) and w.treated and care_rng.randf() < CHEST_REOPEN_CHANCE:
			w.treated = false
			w.closed = false
			if rng.randf() < TENSION_CHANCE:
				w.tension_in = rng.randf_range(TENSION_DELAY_S.x, TENSION_DELAY_S.y)
			reopened += 1
	if reopened > 0:
		update_state(0.0)
	return reopened


## Host only. A blast `distance` metres away within `radius` (BLAST_RADIUS, doubled indoors):
## overpressure (deafness, a concussion check, a chance of blast lung, some impact) and, up
## close, burns. `ear_pro` (electronic ear protection) halves the deafness.
func add_blast(distance: float, radius: float, ear_pro := false) -> void:
	if dead or distance > radius:
		return
	var closeness := clampf(1.0 - distance / radius, 0.0, 1.0)
	deaf_left = maxf(deaf_left, lerpf(BLAST_DEAF_S.x, BLAST_DEAF_S.y, closeness) * (0.5 if ear_pro else 1.0))
	impact = minf(impact + BLAST_IMPACT * closeness, 1.0)
	if rng.randf() < BLAST_CONCUSSION_CHANCE * closeness:
		_concuss()
	if rng.randf() < BLAST_LUNG_CHANCE * closeness:
		blast_lung = true
	if distance < BURN_RADIUS:
		burn = minf(burn + lerpf(BLAST_BURN.x, BLAST_BURN.y, 1.0 - distance / BURN_RADIUS), 1.0)
	update_state(0.0)


## Host only. A fall (or being thrown) from `height` metres: see FALL_SAFE_M.
func add_fall(height: float) -> void:
	if dead or height < FALL_SAFE_M:
		return
	if height > FALL_HARD_M:
		var fatal := FALL_FATAL_CHANCE * clampf((height - FALL_HARD_M) / (FALL_FATAL_M - FALL_HARD_M), 0.0, 1.0)
		if rng.randf() < fatal:
			kill()
			return
	var t := clampf((height - FALL_SAFE_M) / (FALL_HARD_M - FALL_SAFE_M), 0.0, 1.0)
	pain_wounds = minf(pain_wounds + lerpf(FALL_PAIN.x, FALL_PAIN.y, t), 1.0)
	if rng.randf() < lerpf(FALL_FRACTURE_CHANCE.x, FALL_FRACTURE_CHANCE.y, t):
		var bone: StringName = BodyMap.LEG_BONES[rng.randi() % BodyMap.LEG_BONES.size()]
		if not has_fracture([bone], false):
			_add_wound(BodyMap.BONES[bone][3], "fracture", FEMUR_RATE if String(bone).begins_with("femur") else 0.0, bone)
	update_state(0.0)


## Host only. Burns over `share` of the body (fire, burning vehicles).
func add_burn(share: float) -> void:
	if dead:
		return
	burn = clampf(burn + share, 0.0, 1.0)
	update_state(0.0)


## Host only. A shot fired indoors close by (`amount` 1 per shot); past NOISE_DEAF the hearing
## is muffled for NOISE_DEAF_S. Nothing with ear protection.
func add_noise(amount: float, ear_pro := false) -> void:
	if dead or ear_pro:
		return
	noise += amount
	if noise >= NOISE_DEAF:
		deaf_left = maxf(deaf_left, NOISE_DEAF_S)


## Host only. A flashbang's ringing ears for `seconds` (none with ear protection).
func deafen(seconds: float, ear_pro := false) -> void:
	if not dead and not ear_pro:
		deaf_left = maxf(deaf_left, seconds)


func _options(a: StringName, b: StringName) -> Array[StringName]:
	var out: Array[StringName] = [a, b]
	return out


func _task(part: StringName, kind: String, item: StringName, options: Array[StringName] = []) -> Dictionary:
	if options.is_empty():
		return {"part": part, "kind": kind, "item": item}
	return {"part": part, "kind": kind, "item": options[0], "items": options}


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
	access = {}
	infusion = {}
	care_note = ""
	for lung in LUNGS:
		lung_collapse[lung] = 0.0
		lung_fluid[lung] = 0.0
	_spell_wake_s = 0.0
	_low_spo2_s = 0.0
	_out_s = 0.0
	_pain_over_s = 0.0
	deaf_left = 0.0
	noise = 0.0
	blast_lung = false
	burn = 0.0
	burn_dressings = 0
	still_s = 0.0
	blanket = false
	heart_rate = HR_REST
	_hr_danger_s = 0.0
	for id: StringName in DRUGS:
		drug_level[id] = 0.0
		drug_depot[id] = 0.0


## Host only: steps the simulation by `dt` seconds.
func advance(dt: float) -> void:
	if dead:
		return
	_time += dt
	concussion_left = maxf(concussion_left - dt, 0.0)
	knockout_left = maxf(knockout_left - dt, 0.0)
	winded_left = maxf(winded_left - dt, 0.0)
	stagger_left = maxf(stagger_left - dt, 0.0)
	deaf_left = maxf(deaf_left - dt, 0.0)
	noise = maxf(noise - NOISE_FADE_PER_S * dt, 0.0)
	treating_left = maxf(treating_left - dt, 0.0)
	pain_wounds = maxf(pain_wounds - PAIN_FADE_PER_S * dt, 0.0)
	impact = maxf(impact - IMPACT_FADE_PER_S * dt, 0.0)
	_advance_morphine(dt)
	_advance_drugs(dt)
	# Bleeding, scaled by what the heart still pushes out.
	blood = maxf(blood - bleed_rate() / 60.0 * dt / BLOOD_L, 0.0)
	if not infusion.is_empty():  # the only way blood comes back
		var ml := minf(float(infusion.left), infusion_rate() * dt)
		infusion.left = float(infusion.left) - ml
		blood = minf(blood + ml / 1000.0 / BLOOD_L, 1.0)
		if float(infusion.left) <= 0.001:
			infusion = {}
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
				lung_collapse[_lung_of(w)] = 1.0
				w.arrest_in = TENSION_ARREST_S  # tension pneumothorax
		elif float(w.arrest_in) >= 0.0:  # ...but not this one: only the needle does
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
	if blast_lung:  # no field fix: both lungs slowly fill
		for lung in LUNGS:
			lung_fluid[lung] = minf(float(lung_fluid[lung]) + BLAST_LUNG_FLUID_PER_S * dt, maxf(float(lung_fluid[lung]), BLAST_LUNG_MAX))
	_advance_lungs(dt)
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
## still going in, "x" total trauma, "a" the line [kind, gauge, part, pressure] and "v" the
## bag running [item, mL, mL left] (empty arrays for none), "l" the lungs [left collapse,
## left fluid, right collapse, right fluid]. Flag 64 (coming round) only makes the start of the wake
## countdown go out at once; clients read the countdown itself from "t". Flag 128: pain has
## been held over the knockout threshold long enough (pain_knocks_out).
func to_net() -> Dictionary:
	var list: Array = []
	for w in wounds:
		var wound_flags := (1 if w.get("packed", false) else 0) | (2 if w.get("tension", false) else 0) \
			| (4 if w.get("clamped", false) else 0) | (8 if w.get("closed", false) else 0)
		list.append([String(w.part), w.kind, snappedf(float(w.rate), 0.001), 1 if w.treated else 0, String(w.name), wound_flags])
	var flags := (1 if unconscious else 0) | (2 if arrest else 0) | (4 if dead else 0) | (16 if npa else 0) | (32 if airway_blocked else 0) \
		| (64 if wake_left > 0.0 else 0) | (128 if _pain_over_s >= PAIN_KNOCKOUT_S - 0.001 else 0) \
		| (256 if hypothermic() else 0) | (512 if blast_lung else 0) | (1024 if blanket else 0)
	var timers := {}
	for key: String in TIMERS:
		if float(get(key)) > 0.0:
			timers[key] = snappedf(float(get(key)), 0.1)
	var tq := {}
	for part: StringName in tourniquets:
		tq[String(part)] = [int(tourniquets[part].count), int(tourniquets[part].rushed)]
	return {"b": snappedf(blood, 0.001), "p": snappedf(pain_wounds, 0.01), "i": snappedf(impact, 0.01),
		"f": flags, "w": list, "q": tq, "t": timers, "o": snappedf(spo2, 0.5), "m": snappedf(morphine_level, 0.01),
		"d": snappedf(morphine_depot, 0.01), "x": snappedf(trauma_level, 0.01),
		"a": [] if access.is_empty() else [access.kind, int(access.gauge), String(access.part), 1 if access.pressure else 0],
		"v": [] if infusion.is_empty() else [String(infusion.item), int(infusion.ml), snappedf(float(infusion.left), 1.0)],
		"l": [snappedf(float(lung_collapse[LUNGS[0]]), 0.01), snappedf(float(lung_fluid[LUNGS[0]]), 0.01),
			snappedf(float(lung_collapse[LUNGS[1]]), 0.01), snappedf(float(lung_fluid[LUNGS[1]]), 0.01)],
		"h": snappedf(heart_rate, 1.0), "g": _drugs_net(), "u": [snappedf(burn, 0.01), burn_dressings]}


func _drugs_net() -> Dictionary:
	var out := {}
	for id: StringName in DRUGS:
		if drug_total(id) > 0.0:
			out[String(id)] = [snappedf(float(drug_level[id]), 0.01), snappedf(float(drug_depot[id]), 0.01)]
	return out


## Rebuilds this copy from a peer's net_state (clients).
func apply_net(state: Dictionary) -> void:
	blood = float(state.get("b", 1.0))
	pain_wounds = float(state.get("p", 0.0))
	impact = float(state.get("i", 0.0))
	spo2 = float(state.get("o", SPO2_NORMAL))
	morphine_level = float(state.get("m", 0.0))
	morphine_depot = float(state.get("d", 0.0))
	trauma_level = float(state.get("x", 0.0))
	var line: Array = state.get("a", [])
	access = {} if line.is_empty() else {"kind": String(line[0]), "gauge": int(line[1]), "part": StringName(line[2]), "pressure": int(line[3]) != 0}
	var bag: Array = state.get("v", [])
	infusion = {} if bag.is_empty() else {"item": StringName(bag[0]), "ml": int(bag[1]), "left": float(bag[2])}
	var lungs: Array = state.get("l", [0.0, 0.0, 0.0, 0.0])
	for i in LUNGS.size():
		lung_collapse[LUNGS[i]] = float(lungs[i * 2])
		lung_fluid[LUNGS[i]] = float(lungs[i * 2 + 1])
	heart_rate = float(state.get("h", HR_REST))
	var given: Dictionary = state.get("g", {})
	for id: StringName in DRUGS:
		var entry: Array = given.get(String(id), [0.0, 0.0])
		drug_level[id] = float(entry[0])
		drug_depot[id] = float(entry[1])
	var flags := int(state.get("f", 0))
	unconscious = flags & 1 != 0
	arrest = flags & 2 != 0
	dead = flags & 4 != 0
	npa = flags & 16 != 0
	airway_blocked = flags & 32 != 0
	_pain_over_s = PAIN_KNOCKOUT_S if flags & 128 != 0 else 0.0
	blast_lung = flags & 512 != 0
	blanket = flags & 1024 != 0
	still_s = HYPOTHERMIA_STILL_S if flags & 256 != 0 else 0.0  # clients only need hypothermic()
	var burns: Array = state.get("u", [0.0, 0])
	burn = float(burns[0])
	burn_dressings = int(burns[1])
	wounds.clear()
	for entry: Array in state.get("w", []):
		var wound_flags := int(entry[5]) if entry.size() > 5 else 0
		wounds.append({"part": StringName(entry[0]), "kind": String(entry[1]), "rate": float(entry[2]),
			"treated": int(entry[3]) != 0, "name": StringName(entry[4]), "packed": wound_flags & 1 != 0,
			"tension": wound_flags & 2 != 0, "clamped": wound_flags & 4 != 0, "closed": wound_flags & 8 != 0,
			"tension_in": -1.0, "arrest_in": -1.0})
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


## The lung a chest wound is on (its name), the right one if it doesn't say.
func _lung_of(w: Dictionary) -> StringName:
	return w.name if w.name in LUNGS else LUNGS[1]


## Each lung heads for its collapse (tension: full; an unsealed chest wound: partial; else
## re-expanding once sealed), and fills with the blood its chest wounds bleed (see LUNGS).
func _advance_lungs(dt: float) -> void:
	for lung in LUNGS:
		var target := 0.0
		for w in wounds:
			if w.kind != "chest" or _lung_of(w) != lung:
				continue
			if w.get("tension", false):
				target = 1.0
			elif not w.treated:
				target = maxf(target, OPEN_CHEST_COLLAPSE)
			lung_fluid[lung] = minf(float(lung_fluid[lung]) + rate_now(w) * cardiac_output() / 60.0 * dt / HEMOTHORAX_L, FLUID_MAX)
		var now := float(lung_collapse[lung])
		lung_collapse[lung] = move_toward(now, target, (COLLAPSE_PER_S if target > now else 1.0 / REEXPAND_S) * dt)


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
	heart_rate = 0.0
	_hr_danger_s = 0.0


## CPR or a shock worked: the heart beats again (the casualty stays out until every cause of
## unconsciousness is gone, as always).
func _restart_heart() -> void:
	arrest = false
	arrest_left = 0.0
	heart_rate = HR_RESTART
	_hr_danger_s = 0.0
	_low_spo2_s = 0.0


## Epinephrine's wake-up roll can work: out with no cause left but a concussion knockout (or
## already coming round).
func _epi_can_wake() -> bool:
	var causes := unconscious_causes()
	return causes.is_empty() or causes == [&"knockout"]


## Drugs go in from their depots and wear off (DRUGS); the heart rate heads for its target,
## and racing or too slow for HR_DANGER_S stops the heart.
func _advance_drugs(dt: float) -> void:
	for id: StringName in DRUGS:
		var d: Dictionary = DRUGS[id]
		var level := float(drug_level[id]) * pow(0.5, dt / float(d.half_life_s))
		var depot := float(drug_depot[id])
		if depot > 0.0:
			var step := minf(depot, dt / float(d.absorb_s))
			depot -= step
			level += step
		drug_level[id] = 0.0 if level < 0.001 and depot <= 0.0 else level
		drug_depot[id] = depot
	if arrest:
		heart_rate = 0.0
		return
	heart_rate = move_toward(heart_rate, heart_rate_target(), HR_CHANGE_PER_S * dt)
	if heart_rate > HR_DEADLY_FAST or heart_rate < HR_DEADLY_SLOW:
		_hr_danger_s += dt
		if _hr_danger_s >= HR_DANGER_S:
			_start_arrest()
	else:
		_hr_danger_s = 0.0


func _concuss() -> void:
	var mult := 2.0 if _time - _last_concussion < SAME_FIGHT_S else 1.0
	_last_concussion = _time
	var knockout := 0.0
	if rng.randf() < CONCUSSION_KO_CHANCE:
		knockout = rng.randf_range(CONCUSSION_KO_S.x, CONCUSSION_KO_S.y) * mult
		knockout_left = maxf(knockout_left, knockout)
	concussion_left = maxf(concussion_left, knockout + CONCUSSION_S * mult)
