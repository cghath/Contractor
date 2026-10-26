# Contractor: Fallen — the body: metabolism, wounds, infection, sleep, water, seasons

Survival depth past today's survival games and medical depth past SCUM (call 14), on the
medical system Contractor already has. Covers the metabolism (call 14), the fever clock and the
cure (calls 10, 15, 46), sleep (call 47), water and hygiene (call 48), the seasons on the body
(call 34), the body screen and its skill gate (call 58), and the world options that scale it
(call 49). Written 2026-10-26.

Built on: `Vitals` and `WoundModel` (per-part wounds with voxel hit volumes; bleeding classes
arterial, junctional, venous, internal; tension and chest wounds, airway, fractures and pelvis,
burns, hypothermia; blood volume, pulse, pressure, arrest and CPR, defib, epinephrine, fluids
and access; triage; pain; the care log), the treatment items (tourniquets, packing, chest
seals and needles, airways, splints, pelvic binders, IVs, saline, blood, morphine,
epinephrine, the AED, the pulse oximeter), the medic role and `medic_only` items,
`Consumables` (food and water doses, S1's hunger and thirst), `DayNight` weather.

## 1. The metabolism (call 14)

Replaces S1's two bars with a body, on `Vitals` (replicated like stamina, host-authoritative,
simulated in the same `_sim_left` step):

| Store | Range | Drains by | Filled by | Low | Empty |
|---|---|---|---|---|---|
| **calories** | 0-4,000 kcal | basal 1,800/world day + work (carrying, running, building, cold) | food (each item's kcal) | stamina return slower, healing slower, mood -| blood volume loss slowly, collapse |
| **water** | 0-4 l | 2.5 l/day + heat, work, fever, diarrhoea | water, wet food | thirst: aim shake, stamina | faster blood volume loss, collapse in ~3 days |
| **protein** | 0-100 | rebuilding (wound healing uses it) | meat, fish, beans, eggs | healing halves | wounds stop healing |
| **carbs** | 0-100 | fast energy (sprinting) | bread, rice, sugar, potatoes | sprint shorter | shakes |
| **fat** | 0-100 | slow energy, warmth reserve | oils, meat, nuts, cheese | colder faster | calories drain faster |
| **vitamins** (C, D, iron) | 0-100 each | slow | fruit, greens, sun (D), liver (iron) | C: wounds reopen (scurvy) at weeks; D: bones heal slower, mood; iron: fatigue, blood regenerates slower | the illness |
| **sleep** | 0-100 | awake time, faster carrying and fighting | sleep (bed > bedroll > ground) | stamina return slower, aim shake, senses dulled (the stealth model's sight and hearing ranges shrink for you) | microsleeps: the screen dips, a fall |
| **warmth** | core temperature 35-39 °C | cold air, wind, wet clothes, snow, water; fever raises it | clothes by layer, fire, stove, a bed, movement, hot food and drink | shivering (aim, stamina), slow hands (treatments and builds slower) | hypothermia (the existing wound) / heat stroke |
| **hygiene** | 0-100 | days without washing, blood and gore on you, dirty water | washing (water, soap better), clean clothes | wound infection risk up, flies, smell (the dead's smell sense: survival_world.md §5) | dysentery risk, lice (a moodlet) |

Readable, not a spreadsheet: the body screen shows filled rings with trend arrows and words
("hungry", "parched", "running on empty", "frozen through"); numbers on hover (call 58).

**Food** items get `kcal`, `protein`, `carbs`, `fat`, `vitamins`, `water`, `spoils_days`
(by season: summer halves it, a fridge or canning stops it, smoking stretches it), `raw`
(raw meat and dirty water carry a sickness chance; cooking fixes it). Eating raw or rotten
gives the moodlet and a chance of food poisoning (vomiting: calories and water lost).

## 2. Wounds, infection, surgery (call 14)

The wound model stays; survival adds what a hospital isn't there to do:

- **Wound infection staging**, per wound: clean → contaminated (dirty dressing, dirt, a bite,
  dirty water on it, low hygiene) → infected (redness, pain, fever starts: a day) → **sepsis**
  (two to three days unchecked: fever, racing pulse, pressure down, delirium) → death.
  Cleaning (water, better boiled; antiseptic best), a clean dressing changed daily, and
  **antibiotic courses** (a course is 5 doses over 5 world days, not one pill; stopping early
  lets it come back) move it back a stage. Tetanus from rusty metal (a rare, nasty stage).
- **Field surgery** (the medical skill gates it, survival_rpg.md): remove a bullet or fragment
  (else the wound stays contaminated and heals slower), clean and debride, **stitch** (a
  stitched wound heals in days instead of weeks), set a fracture (the splint we have, then
  weeks of healing: a limb in a splint is weaker; a badly set bone heals crooked), drain an
  abscess, amputate (the last resort for gangrene: a survivor with one hand lives, with
  moodlets and skill penalties).
- **Healing over days**: wounds heal with time, protein, sleep and warmth; infection, cold,
  hunger and fever stop it. A deep wound takes a world week; a fracture three. The body screen
  shows the days left and why it's slower.
- **Blood**: blood types on every Person (survival_rpg.md's background may say "O negative");
  transfusions of the wrong type are a reaction; a settlement's blood stock (donated by
  settlers, kept cold) is a medical asset; iron and food rebuild blood over days.
- **Heat stroke** (summer, the desert): the mirror of hypothermia: water, shade, rest.
- **Companion medics** do all of this for you, by their skill (survival_people.md §6); a
  settlement **clinic** (beds, a stove for boiling, a cabinet) raises what can be done and
  draws people (survival_world.md §4).

## 3. The fever clock and the cure (calls 10, 15, 46)

A **bite** (a zombie's `bite` hit class) on a non-immune Person starts the clock, **a world
week long** at the default (call 80; the world option scales it):
- **Incubation** (hidden): day 1; the wound is just a bite.
- **Fever** (days 2-4): temperature up, stamina return slower, thirst faster; companions
  notice ("you're burning up"); the body screen's infection layer shows it by skill.
- **Delirium** (days 5-6): vision sways, aim worsens, senses dulled; companions worry; the
  person says odd things (lines by tag).
- **Collapse** (day 7): down; dies and **rises** as a zombie in their kit within minutes
  unless the head is destroyed or they're put down before.
Antibiotics **pause** the clock a world day per course; rest in a bed and good food slow it
(x0.7); a doctor's care slows it more (x0.5). The **serum** cures at any stage before collapse.
Rare finds (hospital, the lab, ARCHE bunkers: survival_world.md §7) and the **chain**: a doctor
or your own medical skill at the gate level, a hospital or lab zone's equipment (a centrifuge,
a fridge, power), and **an immune Person's blood** (the immunity roll: IMMUNE_CHANCE Proposed
3%, fitness and fieldcraft raise it to ~6%; immunity is discovered when a bite never turns, or
by a test at the lab). A made serum is one dose; the chain can be run again. The enclave's price
is often this (call 56).

A **companion** on the clock: send them away (they become a lone survivor on the clock in the
world sim; the roster's moodlet is mild), keep and treat (the settlement's mood follows the
outcome), put them down (a heavy moodlet, worse for friends; the body stays). A **player** at
collapse: permadeath (call 13); the newcomer or the takeover (call 51).

## 4. Sleep (call 47)

The sleep store above. **Sleeping**: in a bed (best), a bedroll, or the ground (worst: slow
restore, cold). Sleep **passes world time at speed** (Proposed x12) for everyone asleep; the
host's world keeps ticking (the sim's far tick runs at the sped-up rate; live zombies and
groups near the sleepers run at normal rate, so a horde takes real time to arrive). A **watch**
(a companion or settler on the guard job, or a player awake) wakes the sleepers when the
stealth model's awareness states rise near them or a noise ring lands; no watch means waking to
what's already in the room. Sleeping outdoors in winter is a cold risk (warmth drains while
asleep without a fire). Nightmares (a moodlet after a horde or a death) cut the restore.

## 5. Water and hygiene (call 48)

Sources: bottles and cans (loot), **taps** that still run in some buildings (a zone's water
tower or pump house intact or repaired: survival_building.md §8), wells, rivers, lakes, the
dam (clean), rain barrels, snow (melted on a fire). Each source has a **quality**: clean,
questionable, dirty; raw water carries a **dysentery** chance by quality (river 10%, puddle
40%, the dam 0%, Proposed): vomiting and diarrhoea for a day or two, calories and water lost
fast, a moodlet, a real killer for the weak. **Treatment**: boiling (a pot and a fire: 10 min
world time), filters (a piece or a hand filter item, wears), tablets (loot). The desert
region makes water the planning problem (survival_world.md §3). **Hygiene** as in §1: washing
(a basin, a river, a bath piece; soap doubles it), clean clothes (washing as a job), blood and
gore on you (the masking play, call 53, costs hygiene and raises infection risk).

## 6. Seasons on the body (call 34)

- **Winter**: cold air and wind drain warmth fast; wet clothes are deadly; layered clothes
  (found or sewn: a tailoring recipe line in survival_rpg.md) and a fire or stove indoors; snow
  melted for water; frostbite on exposed hands and face at length (a wound; fingers lost in the
  worst case); the dead slow but linger near warmth.
- **Summer**: heat stroke, thirst x1.5, food spoils in half the time, flies on the unwashed,
  wildfires from careless fires (a world event), bloaters worse.
- **Spring and autumn**: rain and wet, mud (slower, dirtier), harvest and planting windows
  (survival_building.md §6).

## 7. The body screen (call 58)

One screen: a rotatable figure of the Person with layers you toggle (wounds, bones, infection,
temperature, wetness, clothing); each part's state in words first ("left forearm: deep bite,
bleeding slowly, dirty dressing, fever in 2 days") and numbers on hover; the metabolism panel
beside it (rings and trends); treatments dragged onto a part (or the existing interaction
menu). The same screen opens on a companion or a casualty. **What you can see is gated by
medical skill** (survival_rpg.md's medical line): a novice sees "hurt, bleeding, hot"; a
trained medic sees the wound classes and the infection stage; a doctor sees everything
including days-left estimates; a companion doctor can read it for you (talk: "how is she?").
The HUD keeps only the small signs: a stamina bar, the needs as two or three small icons that
appear when low, shivering and the screen's edge dimming when the body is failing.

## 8. World options (call 49)

"Needs and medical harshness" at New world: metabolism rates (x0.5 to x2), the infection
clock length (2 to 6 world days), serum rarity (common to a chain only), cold and heat severity.
The other options (dead, loot, living world) are in their docs.

## 9. Performance

The metabolism is a handful of floats per Person stepped per world minute (the same `_sim_left`
step as the wound model); far Persons step on the world sim's far tick in bulk. Infection and
healing step per world hour. Nothing per frame but the HUD.

## 10. Tests (phase A for §1, §4, §5; phase D for §2, §3, §6)

`survival` suite (extending S1's): calories, water and sleep drain and fill at the rates and
with the effects; raw water rolls dysentery and boiled doesn't; a cold wet night drains warmth
and a fire holds it; sleep passes time at speed and a watch wakes the sleepers for a chasing
zombie; a bite starts the clock, antibiotics pause it, the serum cures it, collapse rises; an
immune Person never turns; a contaminated wound stages to sepsis unchecked and back with a
course; surgery removes a fragment and the wound heals faster; the body screen hides the
infection stage from a novice and shows it to a doctor.

## 11. Calls answered (2026-10-26)

- Metabolism at realistic rates with generous warning (call 78): §1 as written.
- Surgery: the full set now, skill-gated with tools and a place (call 79); **permanent
  consequences** (crooked bones, a limp, amputations changing what a survivor can hold, scars)
  are planned for later, not phase D.
- The fever clock is a **world week** (call 80): §3 updated.
- Sicknesses (call 81): dysentery and food poisoning (§5), **colds, flu and pneumonia** (from
  cold, wet and crowding; a cold is a moodlet and a cough that is noise for the stealth model,
  flu a few days down, pneumonia dangerous without antibiotics and warmth; spreads between
  people in a settlement by contact and shared bunks), **tetanus and gangrene** (§2), and the
  **deficiency illnesses** (§1: scurvy, rickets, anaemia over weeks, fixed by food).
