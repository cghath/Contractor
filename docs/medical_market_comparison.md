# Medical systems compared: shooters and mods

Researched 2026-10-12. Compares Contractor's medical system with every shooter (and Arma mod) we
found whose medical goes past a basic "downed, revive, full health" loop.

- **Y** = has it. **P** = partial (a simpler or optional form, or only part of the criterion).
  **N** = not found / not present.
- Numbers in brackets point to the source list below. Obvious cells (a plain "has bleeding and
  bandages" in a game known for it) may go unsourced; every non-obvious Y or P has a source.
- Contractor cells are checked against this repo's code, not the design doc. File references are
  in the source list (C1 to C15).
- The first three columns are the Arma 3 references: a control (vanilla) and two comparison
  stacks (ACE3, then ACE3 + KAT). The stacks are scored as the whole combination, so there are
  no standalone ACE3 or KAT columns. Other Arma 3 mods (PIR, Lifeline) are scored on top of
  vanilla. No Arma column includes LAMBS, VCOM or other AI mods.
- Criteria 17 to 30 were picked from Contractor's own medical features, so Contractor scores
  full marks there by construction. Read the general score (criteria 1 to 16) for the fairer
  market comparison.

## Columns

| Code | Game or mod |
|---|---|
| Arma 3 (control) | Vanilla Arma 3: hit-point damage, vanilla Revive, First Aid Kit and Medikit |
| A3 + ACE3 (comp 1) | Arma 3 with ACE3 medical |
| A3 + ACE3 + KAT (comp 2) | Arma 3 with ACE3 and KAT Advanced Medical stacked, scored as the combination |
| PIR | Project Injury Reaction (Arma 3 mod) |
| LLR | Lifeline Revive AI (Arma 3 mod), scored on its own damage model without ACE |
| ARF | Arma Reforger, base game |
| RACE | ACE for Reforger: ACE Medical Core + Hitzones + Circulation + Breathing + Medical AI, and ACE Carrying |
| EFT | Escape from Tarkov |
| ABI | Arena Breakout: Infinite |
| GZW | Gray Zone Warfare |
| DZ | DayZ |
| SCUM | SCUM |
| PZ | Project Zomboid (survival, firearms are secondary; included for its wound care) |
| SQ | Squad |
| HLL | Hell Let Loose |
| RON | Ready or Not |
| GB | Ground Branch |
| **CTR** | **Contractor (ours)** |

## The table

### General criteria (1 to 16)

| # | Criterion | Arma 3 (control) | A3 + ACE3 (comp 1) | A3 + ACE3 + KAT (comp 2) | PIR | LLR | ARF | RACE | EFT | ABI | GZW | DZ | SCUM | PZ | SQ | HLL | RON | GB | CTR |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Per-limb / per-part damage with effects | Y[1] | Y[3] | Y[3] | P[10] | P[11] | Y[12] | Y[15] | Y[18] | Y[21] | Y[23] | P[25] | Y[27] | Y[29] | N | N | Y[33] | N | Y[C1] |
| 2 | Bleeding with types or rates | P[1] | Y[3] | Y[3] | P[10] | P[11] | P[12] | Y[15] | Y[18] | Y[21] | Y[23] | P[25] | P[27] | P[29] | P[31] | P[32] | P[33] | N | Y[C2] |
| 3 | Tourniquets | N | Y[3] | Y[3] | N | N | Y[12] | Y[12] | Y[18] | P[21] | Y[23] | N | Y[28] | N | N | N | N | N | Y[C3] |
| 4 | Blood volume and transfusion / IV fluids | N | Y[3] | Y[6] | N | P[11] | Y[12] | Y[15] | N | N | Y[23] | Y[25] | P[27] | N | N | N | N | N | Y[C2] |
| 5 | Pain and painkillers | N | Y[3] | Y[3] | N | P[11] | Y[12] | Y[15] | Y[18] | Y[21] | Y[23] | P[26] | Y[28] | Y[29] | N | N | N | N | Y[C4] |
| 6 | Fractures and splints | N | Y[3] | Y[8] | N | N | N | N | Y[18] | Y[21] | Y[23] | Y[26] | Y[28] | Y[29] | N | N | N | N | Y[C5] |
| 7 | Unconsciousness driven by the body (not just a revive timer) | P[1] | Y[3] | Y[3] | P[10] | P[11] | Y[12] | Y[15] | N | P[21] | Y[24] | Y[25] | N | N | P[31] | P[32] | N | N | Y[C4] |
| 8 | Cardiac arrest, CPR / defibrillation | N | Y[3] | Y[7] | N | P[11] | N | Y[15][17] | N | N | N | P[25] | N | N | N | N | N | N | Y[C6] |
| 9 | Airway management | N | N | Y[7][9] | N | N | N | Y[15] | N | N | N | N | N | N | N | N | N | N | Y[C7] |
| 10 | Drag / carry casualties | N | Y[5] | Y[5][7] | Y[10] | N | N | Y[16] | N | N | N | N | N | N | N | N | N | N | Y[C8] |
| 11 | AI medics treat others | Y[1] | Y[4] | Y[4] | Y[10] | Y[11] | Y[13] | Y[15] | N | N | N | N | N | N | N | N | N | N | Y[C9] |
| 12 | AI self-treatment | P[1] | Y[4] | Y[4] | P[10] | N | P[13] | P[15] | Y[19] | P[21] | N | N | N | N | N | N | N | N | Y[C9] |
| 13 | Triage (cards or priority rules) | N | Y[3] | Y[3] | N | N | N | N | N | N | N | N | N | N | N | N | N | N | Y[C10] |
| 14 | Field surgery / stitching | N | Y[3] | Y[8] | N | N | N | N | Y[18] | Y[21] | Y[23] | N | Y[28] | Y[29] | N | N | N | N | Y[C11] |
| 15 | Medication dosing / overdose | N | Y[4b] | Y[7] | N | N | N | Y[15] | P[20] | N | N | N | P[28] | P[30] | N | N | N | N | Y[C4] |
| 16 | Injury that persists past the fight (between raids, missions or sessions) | N | N | N | N | N | N | N | Y[20] | N | N | Y[25] | Y[27] | Y[29] | N | N | P[34] | N | Y[C12] |

### Criteria from Contractor's distinct features (17 to 30)

| # | Criterion | Arma 3 (control) | A3 + ACE3 (comp 1) | A3 + ACE3 + KAT (comp 2) | PIR | LLR | ARF | RACE | EFT | ABI | GZW | DZ | SCUM | PZ | SQ | HLL | RON | GB | CTR |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 17 | Wound channel traced through anatomy (named vessels, organs, bones hit by distance from the channel) | N | N | N | N | N | N | P[15] | N | N | P[23] | N | N | N | N | N | N | N | Y[C1] |
| 18 | Hits resolved on the body's real shape (0.5 cm voxels, separate male and female bodies), not boxes | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | Y[C1] |
| 19 | Bleed class decides the fix: arterial (tourniquet), venous (bandage), junctional (packing), internal (surgery) | N | P[3] | P[3] | N | N | N | P[15] | P[18] | P[21] | P[23] | N | N | P[29] | N | N | N | N | Y[C2] |
| 20 | Internal torso bleeding stopped only by a surgical clamp (AI: medics only) | N | N | P[9] | N | N | N | N | N | N | P[23] | N | N | N | N | N | N | N | Y[C11] |
| 21 | Per-lung chest trauma: open and tension pneumothorax, hemothorax; seal and needle | N | N | Y[7][9] | N | N | N | P[15] | N | N | N | N | N | N | N | N | N | N | Y[C7] |
| 22 | Hidden vitals (SpO2, heart rate, breathing) read as clinical signs; a monitor gives numbers | N | P[3] | Y[7] | N | N | N | P[15] | N | N | N | N | P[27] | N | N | N | N | N | Y[C6] |
| 23 | IV / IO access as its own step, catheter gauges, shock makes IVs slower or miss | N | N | P[7] | N | N | N | N | N | N | N | N | N | N | N | N | N | N | Y[C13] |
| 24 | Brain-fragment wounds: survivable but down, separate from a bullet kill; helmet-stop concussion | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | Y[C14] |
| 25 | Blast trauma: blast lung, burns, overpressure deafness | N | P[3b] | P[3b] | N | N | N | N | P[18] | N | N | N | N | N | N | N | N | N | Y[C14] |
| 26 | Blunt trauma behind armour (pain, winded, cracked ribs from stopped rounds) | N | N | N | N | N | N | N | Y[18] | P[22] | N | N | N | N | N | N | N | N | Y[C14] |
| 27 | Open vs closed breaks and bone-specific injuries (pelvis and binder, collarbone, ribs) | N | N | P[8] | N | N | N | N | N | N | N | N | N | N | N | N | N | N | Y[C5] |
| 28 | AI medic smokes between casualty and threat and drags to cover before treating | N | N | N | N | N | P[14] | N | N | N | N | N | N | N | N | N | N | N | Y[C9] |
| 29 | Moving the casualty interrupts treatment; AI never lifts a casualty someone else is treating | N | P[3] | P[3] | N | N | N | N | N | N | N | N | N | N | N | N | N | N | Y[C8] |
| 30 | Medic role gear: medic-only aid bag, AI non-medics barred from clamp, CPR and defibrillator | P[1] | P[3] | P[3] | N | N | N | N | N | N | N | N | N | N | P[31] | P[32] | N | N | Y[C15] |

> **Control and comps.** All scores are read against three Arma 3 references, which lead the
> table. **Arma 3 (control)** is vanilla Arma 3 medical: hit-point damage, vanilla Revive, First
> Aid Kit and Medikit (4 / 30). **A3 + ACE3 (comp 1)** is Arma 3 with ACE3 medical, the common
> milsim standard (16.5 / 30). **A3 + ACE3 + KAT (comp 2)** is Arma 3 with ACE3 and KAT Advanced
> Medical stacked, the deepest Arma 3 medical setup we found (20.5 / 30). Every column below is
> given as its raw score and its difference from each of the three.

## Scores (Y = 1, P = 0.5)

| Column | General (1-16) | Distinct (17-30) | Total /30 (vs control, vs ACE, vs ACE+KAT) |
|---|---|---|---|
| Arma 3 (control) | 3.5 | 0.5 | 4 (control, -12.5 vs ACE, -16.5 vs ACE+KAT) |
| A3 + ACE3 (comp 1) | 14 | 2.5 | 16.5 (+12.5 vs control, comp 1, -4 vs ACE+KAT) |
| A3 + ACE3 + KAT (comp 2) | 15 | 5.5 | 20.5 (+16.5 vs control, +4 vs ACE, comp 2) |
| ACE for Reforger (medical + carrying) | 11.5 | 2 | 13.5 (+9.5 vs control, -3 vs ACE, -7 vs ACE+KAT) |
| Escape from Tarkov | 8.5 | 2 | 10.5 (+6.5 vs control, -6 vs ACE, -10 vs ACE+KAT) |
| Gray Zone Warfare | 8 | 1.5 | 9.5 (+5.5 vs control, -7 vs ACE, -11 vs ACE+KAT) |
| SCUM | 7.5 | 0.5 | 8 (+4 vs control, -8.5 vs ACE, -12.5 vs ACE+KAT) |
| Arma Reforger (base) | 7 | 0.5 | 7.5 (+3.5 vs control, -9 vs ACE, -13 vs ACE+KAT) |
| Arena Breakout: Infinite | 6.5 | 1 | 7.5 (+3.5 vs control, -9 vs ACE, -13 vs ACE+KAT) |
| Project Zomboid | 6 | 0.5 | 6.5 (+2.5 vs control, -10 vs ACE, -14 vs ACE+KAT) |
| DayZ | 6 | 0 | 6 (+2 vs control, -10.5 vs ACE, -14.5 vs ACE+KAT) |
| Project Injury Reaction (Arma 3) | 4 | 0 | 4 (+0 vs control, -12.5 vs ACE, -16.5 vs ACE+KAT) |
| Lifeline Revive AI (Arma 3) | 4 | 0 | 4 (+0 vs control, -12.5 vs ACE, -16.5 vs ACE+KAT) |
| Ready or Not | 2 | 0 | 2 (-2 vs control, -14.5 vs ACE, -18.5 vs ACE+KAT) |
| Squad | 1 | 0.5 | 1.5 (-2.5 vs control, -15 vs ACE, -19 vs ACE+KAT) |
| Hell Let Loose | 1 | 0.5 | 1.5 (-2.5 vs control, -15 vs ACE, -19 vs ACE+KAT) |
| Ground Branch | 0 | 0 | 0 (-4 vs control, -16.5 vs ACE, -20.5 vs ACE+KAT) |
| **Contractor (ours)** | **16** | **14** | **30 (+26 vs control, +13.5 vs ACE, +9.5 vs ACE+KAT)** |

On the general criteria alone (control 3.5, ACE 14, ACE+KAT 15): Contractor scores 16
(+12.5 vs control, +2 vs ACE, +1 vs ACE+KAT). ACE for Reforger 11.5, Tarkov 8.5, Gray Zone 8,
SCUM 7.5, Reforger 7, Arena Breakout 6.5, Project Zomboid 6, DayZ 6, PIR 4, Lifeline 4, Ready
or Not 2, Squad 1, Hell Let Loose 1, Ground Branch 0.

Notes on reading the scores:

- On the general criteria, the two comps (ACE3 + KAT 15, ACE3 14) are within a point or two of Contractor (16).
  The gap is in criteria 17 to 30, which were chosen from our own feature list.
- A3 + ACE3 + KAT (comp 2) is the strongest outside setup: airway, per-lung chest trauma, blood groups, a vitals
  monitor and fracture surgery. Nothing else we found has a working airway model apart from comp 2
  and ACE for Reforger's Breathing module.
- No other game or mod we found models named blood vessels, hits on a true body shape, brain
  fragments, blast lung, a medic-only clamp for internal bleeding, or AI medics that smoke a
  casualty and never lift one under treatment.
- Extraction shooters (Tarkov, Arena Breakout, Gray Zone) are strong on limbs, bleeds, fractures
  and surgery, but have no AI medics, no CPR and (apart from Gray Zone) no blood volume.
- Squad, Hell Let Loose, Ready or Not and Ground Branch are close to the "basic revive" line.
  They are kept because they were asked for by name.

## Cells we are unsure about

- **Arma 3 base, AI self-treatment (12):** AI do use First Aid Kits on themselves, but we could
  not confirm whether this happens unprompted or only by order. Scored P.
- **Arma 3 base, drag (10):** we found no base-game drag or carry in vanilla Revive. Scored N.
- **PIR and Lifeline Revive AI:** neither has an official feature list we could read in full.
  PIR comes from its Steam changelog and compatibility posts, Lifeline from a Workshop mirror
  and the author's forum post. The "PIR" asked for was taken to be Project Injury Reaction; if
  a different "ACE PIR" was meant, that column needs redoing.
- **Arma Reforger base, AI self-treatment (12):** patch notes confirm AI heal each other (1.2)
  and use smoke when healing downed comrades (1.1). We found no note on AI bandaging themselves.
  Scored P.
- **Arena Breakout: Infinite, tourniquet (3), downed state (7), AI healing (12), blunt damage (26):**
  from guide sites only. Scored P each.
- **Gray Zone Warfare, blunt trauma (26) and persistence (16):** not confirmed either way. Scored N.
- **DayZ, overdose (15):** no reliable source. Scored N.
- **SCUM, unconsciousness (7), blood transfusion (4) and overdose (15):** the wiki pages were
  incomplete. Scored N, P and P.
- **Project Zomboid, overdose (15):** only forum posts (sleeping pills with alcohol). Scored P.
- **Squad, drag (10):** a Reforger forum post compares Reforger unfavourably with "dragging bodies
  in Squad", but the Squad wiki pages we read do not mention dragging. Scored N.
- **Ready or Not:** per-limb damage and bleeding are sourced. Commander Mode tracks officers'
  physical and mental health between missions (P for 16); we found no medkit or teammate healing.
- **Ground Branch:** we found no medical system documented at all (no bleeding, healing or
  revive in any patch notes we read). Scored all N.
- **Comps 1 and 2, criterion 29:** an ACE treatment is cancelled when the medic and patient move
  apart (a range check on the progress bar). Scored P because nothing stops AI moving a casualty
  someone else is treating.

## Sources

Arma 3 and mods

1. Arma 3 Revive (incapacitated state, bleeding out, medic and Medikit vs First Aid Kit, AI revive):
   https://community.bistudio.com/wiki/Arma_3:_Revive
2. Arma 3 damage model (hit points per body part, leg damage forcing a limp):
   https://community.bistudio.com/wiki/Arma_3:_Damage_Description
3. ACE3 medical system (body parts, wound types and bleeding, pain, fractures and splints,
   unconsciousness, cardiac arrest and CPR, IV transfusion, triage, stitching and surgical kits,
   medic-only item settings, treatment interaction rules):
   https://ace3.acemod.org/wiki/feature/medical-system
   - 3b. ACE3 hearing (deafness from explosions and gunfire): https://ace3.acemod.org/wiki/feature/hearing
     Burn wounds: https://github.com/acemod/ACE3/tree/master/addons/medical_damage
4. ACE3 medical AI, "Makes AI units heal themselves and each other" (tourniquet, bandage, splint,
   morphine, epinephrine, CPR): https://github.com/acemod/ACE3/tree/master/addons/medical_ai
   - 4b. ACE3 medication config (per-drug max dose, overdose effects):
     https://github.com/acemod/ACE3/tree/master/addons/medical_treatment
5. ACE3 dragging and carrying: https://ace3.acemod.org/wiki/feature/dragging
6. KAT blood groups and blood IVs (circulation module):
   https://github.com/KAT-Advanced-Medical/KAM/blob/dev-Tomcat/addons/circulation/stringtable.xml
7. KAT items (Guedel tube, King LT, suction, AAT kit for needle decompression and drainage, chest
   seal, pulse oximeter, stethoscope, AED and AED-X monitor, 16g IV, FAST IO, naloxone for morphine
   overdose, TXA overdose rule, stretcher): https://github.com/KAT-Advanced-Medical/KAM/wiki/KAM-Items
8. KAT surgery (check fracture, compound and comminuted fractures, incision, clamp fracture,
   close incision, ultrasound):
   https://github.com/KAT-Advanced-Medical/KAM/blob/dev-Tomcat/addons/surgery/stringtable.xml
9. KAT breathing (pneumothorax, hemopneumothorax with internal bleeding, tension pneumothorax,
   treatment gated by medical level) and airway (obstruction, occlusion):
   https://github.com/KAT-Advanced-Medical/KAM/blob/dev-Tomcat/addons/breathing/stringtable.xml
   https://github.com/KAT-Advanced-Medical/KAM/blob/dev-Tomcat/addons/airway/stringtable.xml
10. Project Injury Reaction (injury reactions, own revive, bandaging from the casualty's IFAK, AI
    aid search radius, fatal bleeding, dragging option):
    https://steamcommunity.com/sharedfiles/filedetails/?id=1665585720
    https://steamcommunity.com/sharedfiles/filedetails/changelog/1665585720
11. Lifeline Revive AI (AI revive players and each other; own damage model with body-part
    injuries, bandages, blood IV, morphine, CPR by action menu):
    https://steamcommunity.com/sharedfiles/filedetails/?id=3343235386 (mirror: https://catalogue.smods.ru/?p=292366)

Arma Reforger

12. Reforger health system (bandage, tourniquet, saline, morphine, unconsciousness from blood loss):
    https://reforger.armaplatform.com/news/boot-camp-health-system
13. Reforger 1.2 (AI commanding, AI heal one another):
    https://reforger.armaplatform.com/news/update-june-26-2024-2
14. Reforger 1.1 (AI use smoke grenades when healing downed comrades):
    https://gamespress.westeu-v2.propressroom.com/Arma-Reforger-Update-11-Guerrilla-Fighters-AI-Improvements-and-New-PvE
15. ACE for Reforger medical (Core: resilience, second chance, pain, morphine and epinephrine;
    Hitzones: heart and femoral artery zones, massive bleeding; Circulation: heart rate, blood
    pressure, hemorrhage classes, cardiac arrest, CPR, drug dosing with overdose and naloxone;
    Breathing: SpO2, airway obstruction, pneumothorax, tension pneumothorax, chest seal, NCD kit;
    Medical AI): https://anvil.acemod.org/dev/components/medical/
16. ACE Carrying for Reforger: https://reforger.armaplatform.com/workshop/5DBD560C5148E1DA-ACECarrying
17. Defibrillation for ACE (Reforger):
    https://reforger.armaplatform.com/workshop/684892630C2DFCA1-DefibrillationforACEDev

Extraction shooters

18. Escape from Tarkov healing (per-part HP, light and heavy bleeds, tourniquet and hemostat,
    fractures and splints, painkillers, CMS and Surv12 surgery, blunt damage through armour,
    contusion): https://eft-ammo.com/wiki/escape-from-tarkov-healing
19. Tarkov AI medicine use: https://escapefromtarkov.fandom.com/wiki/Scavs
20. Tarkov post-raid health and stimulant side effects:
    https://brewminate.com/how-to-heal-after-raid-in-escape-from-tarkov/
21. Arena Breakout: Infinite healing (bleeds, fractures, surgery kits, painkillers, downed in squads):
    https://www.shacknews.com/article/142346/arena-breakout-infinite-healing
    https://pcinvasion.com/arena-breakout-infinite-healing-guide-items-keybinds-and-how-to-do-it
22. Arena Breakout armour blunt damage (guide-level source): https://buffbuff.com/blog/arena-breakout-health-meds
23. Gray Zone Warfare health (bleed levels, tourniquet, splints, painkillers, blood bags, organ
    damage needing a surgical kit, stomach bleeding):
    https://www.destructoid.com/gray-zone-warfare-health-system-explained/
    https://www.dtgre.com/2024/06/gray-zone-warfare-how-medical-or-health.html
24. Gray Zone Warfare teammate revive:
    https://games.gg/de/gray-zone-warfare/guides/gray-zone-warfare-teammate-revival-guide/

Survival games

25. DayZ blood (blood types, saline, blood bag transfusion, shock and unconsciousness, CPR,
    epinephrine): https://dayz.wiki.gg/wiki/Blood  and  https://dayz.fandom.com/wiki/Character_Status
26. DayZ fractures, splints and painkillers/morphine: https://dayz.fandom.com/wiki/Character_Status
27. SCUM injuries (per-part wounds, bleeding, stabilisation, infection, ICU vitals monitor, blood
    level): https://scum.wiki.gg/wiki/Injuries
28. SCUM medical skill and treatment (tourniquet, sutures, splints, painkillers):
    https://scum.fandom.com/wiki/Skills/Medical  and
    https://www.ludo.guide/guide/scum/getting-started/understanding-health-injuries
29. Project Zomboid first aid (per-part wounds, deep wounds and stitching, bullet and glass removal,
    fractures and splints, painkillers): https://pzfans.com/first-aid/
30. Project Zomboid overdose (forum only): https://steamcommunity.com/app/108600/discussions/0/1696095260997607148

Milsim and tactical

31. Squad health and medic (bleeding, field dressings, wounded and incapacitated states, only medics
    heal with a medical kit): https://squad.fandom.com/wiki/Health_Management  and
    https://squad.fandom.com/wiki/Medic
32. Hell Let Loose bandage and medic revive: https://hellletloose.fandom.com/wiki/Bandage
33. Ready or Not bleeding from limb and armour hits: https://readyornot.wiki.gg/wiki/Body_armor
34. Ready or Not Commander Mode (officers' physical and mental health between missions):
    https://itemlevel.net/ready-or-not-commander-mode-guide-in-1-0-roster-therapy-traits/

Contractor (this repo)

- C1. 14 body parts; wound channel traced through 29 named vessels, brain, heart, both lungs and
  long bones; hits on the 0.5 cm voxel body with male and female shapes:
  `scripts/combat/wounds/body_map.gd`, `scripts/combat/wounds/body_volume.gd`
- C2. Arterial, venous, junctional and internal bleeds plus muscle, graze, chest and open-fracture
  bleeding; 6 L blood; bleeding follows cardiac output; IV and IO bags only restore blood:
  `scripts/combat/wounds/wound_model.gd`, `scripts/combat/vitals.gd`
- C3. Tourniquet high and tight, rushed tourniquets, up to 2 per limb: `scripts/combat/wounds/wound_model.gd`
- C4. Pain threshold knockouts; consciousness from SpO2, pain, blood loss, arrest, concussion,
  morphine and total trauma; morphine as a blood level with sedation and slowed breathing:
  `scripts/combat/vitals.gd`, `scripts/combat/wounds/wound_model.gd`
- C5. Named-bone fractures, open and closed breaks by round class, pelvis and binder, collarbone,
  ribs, splints: `scripts/combat/wounds/wound_model.gd`
- C6. Hidden heart rate, SpO2 and breathing; cardiac arrest with a 10-minute window; CPR,
  defibrillator, epinephrine, atropine, adenosine; pulse oximeter gives numbers:
  `scripts/combat/vitals.gd`, `scripts/ui/medical_menu.gd`
- C7. Airway obstruction and NPA; per-lung collapse and blood, tension pneumothorax, chest seal and
  needle: `scripts/combat/wounds/wound_model.gd`
- C8. Fireman's carry and drag; treatment interrupted if treater or casualty moves; AI never lifts
  or drags a casualty another soldier is treating: `scripts/ai/squad_ai.gd` (`_being_treated`)
- C9. AI medics answer by order (team medic, battle buddy, other medic, nearest), screen a casualty
  in the open with smoke, drag to cover, tourniquet while exposed, treat in care order; wounded AI
  self-tourniquet and treat in cover: `scripts/ai/squad_ai.gd`
- C10. Triage cards (minimal, delayed, immediate, expectant) set AI treatment order:
  `scripts/combat/vitals.gd`, `scripts/ai/squad_ai.gd` (`triage_tier`)
- C11. Surgery kit hemostat clamp: the only fix for internal torso bleeding, also closes
  junctional, arterial and chest wounds; flagged medic-only for AI: `scripts/combat/wounds/wound_model.gd`,
  `data/items.json` (`surgical_clamp`)
- C12. Sit-out days back at base for fractures, surgery, blood loss, ribs, burns and blast lung;
  the medbay shortens them: `scripts/campaign/roster.gd`
- C13. IV catheters 10 to 20 gauge with flow and placement time by gauge; IO line; IV misses and
  collapsed veins in shock: `scripts/combat/wounds/wound_model.gd`
- C14. Brain-fragment wounds (out at once, 60% fatal, else out until base); helmet-stop
  concussion; blast lung, burns and blast deafness; plate stops that cause pain, winding and cracked
  ribs: `scripts/combat/wounds/wound_model.gd`, `scripts/combat/vitals.gd`
- C15. Medic's aid bag (medic-only) on the pack; AI non-medics cannot use the clamp, CPR or the
  defibrillator: `data/items.json`, `scripts/actors/soldier.gd`, `scripts/ai/squad_ai.gd`
