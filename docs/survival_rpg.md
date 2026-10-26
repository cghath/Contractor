# Contractor: Fallen — the RPG layer: skills, perks, backgrounds and flaws, crafting

Experience and progression for every survivor (calls 11, 16, 17, 18), character creation
(call 17), what death does to it (calls 13, 51), crafting and the workbench (calls 43, 38),
and the skill gates the other docs lean on (medical diagnosis and surgery, building tiers,
mechanics). Written 2026-10-26. Inspired by Project Zomboid's traits and learn-by-doing, kept
readable.

Built on: `Hiring.candidate` (names, roles, skills as numbers), `Roles` (medic-only items,
role kits), the loadout and inventory, the interaction menu, the existing weapon handling and
movement stats (stamina, carry weight).

## Where the build is (2026-10-26 ~02:30 CDT)

Branch `claude/survival-rpg` (worktree `B:\Contractor\.claude\worktrees\survival-rpg`, from `claude/survival` 1c5b622b):
**phase B's RPG layer, first form, built; R2634 PASS (rpg + survival suites) at 39231fd8.**
- `Rpg` (scripts/survival/rpg.gd) with `RpgLines`, `Perks`, `Backgrounds`: the twelve lines, the call 82 curve, the
  at/below/above rule, survivor levels and 21 perks, creation (15 backgrounds, 15 flaws), the gates table as
  `Rpg.can(s, "stitch")`, the effects and XP sources in section 1 (see CHANGELOG). Saved in the survivor record
  ("rpg"); permadeath wipes it.
- `Crafting` + `data/survival_recipes.json` (hands and fire stations; 7 recipes), `CharacterScreen` (the ] key),
  `SurvivorPicker` on the New world screen.
- **For the other lanes:** building calls `Rpg.xp(s, "building", n)` and reads `Rpg.build_time_mult(s)` and
  `Rpg.can(s, "build_tier_2")`; the body screen reads `Rpg.medical_sees(s)` (0/1/2); companions' lines, teaching
  (`Rpg.server_teach` is a stub), the newcomer's own creation pick, the inventory's Read action for books
  (`Rpg.server_read`), workbench stations and the "later" perks and flaws wait for their systems.
- Not in this pass: pipe guns and the jam test, firearms/archery/mechanics XP (no hooks yet), tool durability.

## 1. Skill lines (call 16)

Twelve lines, each 0-10, levelled by **doing**:

| Line | Levels from | What levels unlock (examples) |
|---|---|---|
| **medical** | treatments done (more for harder ones), diagnoses, surgery | 1 bandage/clean properly; 2 read bleeding classes; 3 splint, stitch; 4 see infection stages, antibiotics courses right; 5 remove fragments; 6 set bones well, transfuse; 7 drain, the clinic's full use; 8 amputate; 9 run the cure chain; 10 teach it |
| **building** | blocks and pieces placed, repairs, blueprints finished | faster builds (-6% per level), tier 2 at 2, tier 3 at 4, steel at 6, integrity shown in numbers at 3, templates at 5 |
| **melee** | hits landed, parries, kills | stamina cost down, heavy swing at 2, parry window wider at 3, silent kill from behind at 4, two-handed mastery at 6 |
| **firearms** | hits, kills, reloads under stress | sway and recoil control, faster reloads, jam clearing at 3, reloading ammo from components at 7 |
| **archery** | hits with bows and crossbows | draw speed, arrow recovery chance, bow making at 4 |
| **scavenging** | containers searched, items found | faster searches, better rolls (+4% per level), spotting hidden caches at 5, reading a place's loot bias at 3 |
| **mechanics** | repairs, parts fitted, wrecks stripped | fit a battery at 1, a tyre at 2, engine work at 4, rebuild a wreck at 6, the dam or plant at 9 |
| **driving** | distance driven, no crashes | handling, fuel use, carts at 1, towing at 3 |
| **cooking** | meals cooked, preserved | meals with better moodlets, smoking at 2, canning at 4, less spoilage |
| **fieldcraft** | fires lit, water treated, tracks read, animals handled, nights outdoors | fire in rain at 2, snares at 2, tracking at 3, horses at 3, foraging knows mushrooms at 4, the immunity roll bonus, weather reading at 5 |
| **fitness** | distance carried and run | carry weight (+3 kg per level), stamina, cold resistance, the immunity roll bonus |
| **stealth** | time unseen near the dead, silent kills, sneaking past awareness states | quieter movement, slower awareness rise, the masking play at 4, crawl among walkers at 7 |

XP per line is a curve **fast early, slow late** (call 82): levels 1-4 need 60/120/240/480 XP (a few real
hours of the work), 5-10 need 1,000 × (n-4)² (a season each, Proposed); doing the thing at your level
earns full XP, below it little, above it (a hard treatment that worked) a lot. **Reading**
(found books and manuals) and **teaching** (a companion with a higher line: "teach me",
survival_people.md §5; a lesson at the settlement is a job) give XP without doing.

## 2. Survivor level and perks (call 16)

Total XP gives a **survivor level** (every 1,000 XP, Proposed, slowing). Each level gives a
**perk pick** from a short list, general, not tied to a line: a bigger pack (+10 l), faster
healing, quieter movement, iron stomach (raw food safer), thick skin (cold), night eyes, steady
hands (treatments and builds faster under stress), a people person (better hiring prices and
standing), a planner (work orders done faster by settlers), light sleeper (wakes on the first
noise ring), second wind (stamina burst once a day). Perks are the visible number to lose at
permadeath and the thing that makes two level-6 medics different.

## 3. Character creation (call 17)

**Blank slate** by default (every line at 0, no perks), or **background + flaws**:
- A **background** starts one line higher (Proposed +3) and a second +1, with a kit flavour
  and a line about who they were: nurse (medical, cooking), paramedic (medical, driving),
  carpenter (building, fitness), electrician (building, mechanics), mechanic (mechanics,
  driving), soldier (firearms, fitness), hunter (archery, fieldcraft), farmer (fieldcraft,
  cooking), chef (cooking, melee: a knife hand), police (firearms, melee), athlete (fitness,
  stealth), burglar (stealth, scavenging), doctor (medical +4, fitness -1), teacher (teaching
  bonus, a people person), kid who grew up on a farm (fieldcraft, animals).
- **Flaws** give **points** that buy lines higher (Zomboid's way): each flaw is -1 to -3
  points' worth of trouble; each line level above the background costs points. Flaws: smoker
  (needs tobacco or a moodlet; a cough), bad knee (slower, no sprint on slopes), short-sighted
  (needs glasses: a loot item, sight range down without), hard of hearing, asthma (stamina),
  weak stomach, hemophobic (useless at blood), coward (courage down, refuses more), hot-headed
  (rage breaks), heavy sleeper (never wakes to the ring), clumsy (drops things, louder), slow
  learner (XP x0.8), thin-skinned (cold), a drinker, insomniac, allergic (certain foods), a
  known face (a group kind starts hostile, by seed).
Backgrounds and flaws apply to companions and world people too (survival_people.md): the
world's doctor is a doctor background; the raider with the bad knee limps.

## 4. Death and the new survivor (calls 13, 51)

Permadeath: XP, level, perks, skills die with the survivor. The new survivor is made from
scratch (blank or background + flaws), enters at the settlement or the nearest edge, or the
player takes over a willing companion (their lines and perks become the player's: a reason to
level companions). Nothing carries over between survivors **except knowledge in the world**:
the journal, the map, the settlement, the companions and what they know are the player's
inheritance (survival_world.md §10). A **legacy** moodlet for the companions who knew the dead.

## 5. Crafting (calls 43, 38)

Recipes are data (`data/survival_recipes.json`): inputs, a tool, a station (hands, a fire, the
workbench tiers 1-3, the forge, the chemistry bench, the loom, the reloading bench), time, the
skill line and level, and the output. Gated by the line's level and the station's tier.

- **Essentials and maintenance**: bandages from cloth (boiled better), splints, torches,
  water filters, smoked and canned food, arrows and bolts, spears and clubs, repairs to
  clothes (the loom and needle), tools and weapons (durability back, parts), reloaded ammo
  (the reloading bench, firearms 7: cases, primers, powder, projectiles; a bad reload is a
  misfire), settlement fixtures (stove, well, smokehouse, lookout, the clinic's cabinet).
- **Improvised weapons and armour** (call 43): pipe guns (single-shot, loud, **unreliable**:
  jam and misfire rates several times a found gun's, wear fast, a small chance to blow up in
  the hand by condition), nail bombs, molotovs, a leaf-spring crossbow, improvised armour from
  tyres, plates and books (heavy, hot, noisy; stops bites and knives, not rifle rounds).
- **Gunsmithing** (call 85): repairing and assembling real guns from **parts** (receivers, barrels,
  bolts, springs, stocks: loot from gun shops, the police station, the base, stripped guns) at
  firearms 8-9 on a gunsmith bench; a gun built from worn parts is worse than a found one until
  the parts are good. Ceramic plates are never crafted.
- **Found guns** stay the real thing (call 38); ammo scarce; **suppressors** rare, found or
  crafted at firearms 6 from a filter and a can, wearing out in a few mags.
- **Clothes and warmth**: sewing from cloth and hides (fieldcraft for tanning), layers that
  matter in winter (survival_medical.md §6).
- **Medicine**: boiled water, antiseptic from alcohol, herbal teas (mild), antibiotics only
  found (or the chemistry bench at medical 8 from mould cultures: slow, rare), the serum from
  the chain.

Crafting takes time with the hands busy (a progress ring; interruptible), uses the tool's
durability, and levels the line. Settlers craft from work orders (survival_building.md §6).

## 6. Skill gates used by the other docs

| Gate | Line, level |
|---|---|
| read bleeding classes / infection stage / full diagnosis | medical 2 / 4 / 7 |
| stitch / remove fragment / set bone well / amputate / run the cure chain | medical 3 / 5 / 6 / 8 / 9 |
| build tier 2 / 3 / steel; see load numbers; templates | building 2 / 4 / 6; 3; 5 |
| fit a battery / tyre / engine / rebuild a wreck / the dam | mechanics 1 / 2 / 4 / 6 / 9 |
| silent kill / two-handed mastery | melee 4 / 6 |
| reload ammo / craft a suppressor | firearms 7 / 6 |
| horses / tracking / mushrooms / weather | fieldcraft 3 / 3 / 4 / 5 |
| masking / crawl among walkers | stealth 4 / 7 |
| teach a line | that line, 2 above the student |

## 7. UI

The character screen: the figure (shared with the body screen), the lines as bars with the
next unlock named, the perks, the background and flaws, the journal's tally (days survived,
kills, people saved). Companions have the same screen, read through your knowledge of them.
Level-ups are a quiet line in the journal and a bark from a companion, not a fanfare.

## 8. Tests (phase B)

`rpg` suite: XP by doing at, below and above level; a level unlocks the gate (a stitch refused
at medical 2, done at 3); a perk pick applied (carry weight); a background's starting lines; a
flaw's points buying a level and its effect (the short-sighted sight range); permadeath wipes
and the takeover inherits; a recipe gated by station and level; a pipe gun's jam rate above a
found gun's; teaching gives XP; reading a manual gives XP.

## 9. Calls answered (2026-10-26)

XP fast early and slow late (call 82, §1); one permanent perk per survivor level from ~20
(call 83, §2); backgrounds +3/+1 and flaws worth 1-3 points, ~15 of each (call 84, §3);
the top end plus **gunsmithing** (call 85, §5).
