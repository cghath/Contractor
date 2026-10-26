# Contractor: Fallen (survival): an open world, persistent, overrun

## Where the build is (2026-10-26 ~06:45 CDT)

- **PHASE B COMPLETE on claude/survival (0996f909)**: building, RPG and people lanes merged; survival, fallenpeople,
  building, rpg PASS (R2646). **Slice B build B2647**: B:\Contractoruilds\contractor-2026-10-26-063915-B2647-fallen-slice-b-0996f909.
- **Phase C started ~06:40**: the world sim (claude/survival-worldsim) and the settlement's work (claude/survival-settlement)
  on Opus lanes; next lanes once the sim lands: the enclave + ARCHE trail + bunkers, trade + the intel layer, mounts.
- Calls now 1-142 (the table below).
- **Phase C core (the world sim) built on `claude/survival-worldsim`** (survival_world.md 2-5, 9, 11-13): groups,
  regions, the judgement, far fights, pressure and hordes across the map, live groups, the catch-up, rumours, goal
  modes; R2652 PASS (worldsim, survival, settlement; a far tick 13 ms for 78 groups); see survival_world.md's "Where the build is".
- **Phase C enclave, ARCHE's trail and bunkers built on `claude/survival-enclave`** (survival_world.md 6-7, survival_medical.md 3;
  calls 15, 46, 56, 62, 66, 68): the enclave's posts, patrols, tolls, price, disguise, break and joining; the trail; bunkers; the
  serum chain; R2658 PASS (enclave, worldsim, survival); see docs/survival_enclave.md.
- **Phase C trade and intel built on `claude/survival-intel`** (survival_world.md 8 and 10; calls 26, 37, 45, 54, 95, 98):
  the value scale and traders' prices, the barter screen, rumours in the talk menu, the journal (7), the radio, landmarks,
  the map's political colour and the settlement's map table; R2656 PASS (intel, worldsim, survival); see docs/survival_intel.md.
- **Phase D of the world built on `claude/survival-seasons`** (calls 28, 30, 34, 53, 55, 59, 60, 92, 113, 137, 140): seasons
  (`Seasons`, `Survival.season()`: weather, winter's frost and frozen dead, the spring thaw horde, summer flags, planting and
  harvest), raids and horde sieges on builds (`Sieges`: chew, pile, climb, vault, squeeze; breach charges; stores taken),
  politics (`Politics`), infrastructure (`Infrastructure`: power, projects, bridges), traps, lures, masking; R2665 PASS (seasons, survival, worldsim, settlement); see docs/survival_seasons.md.
- **Mounts built on `claude/survival-mounts`** (calls 31, 35; horses, bicycles, carts, tie-and-guard, companions riding): R2659: mounts PASS, survival PASS, vehicles single-peer PASS; vehicles host FAIL only on "V does nothing else" (quick_melee on V in autoload/controls.gd, from the melee lane, not mounts); see docs/survival_mounts.md.

### (earlier) 2026-10-26 ~02:15 CDT

- **PHASE A COMPLETE on claude/survival** (c46fef0b + test tweaks): steps 1-8 all in; the metabolism
  (claude/survival-metabolism) and the map (claude/survival-map) lanes merged. Survival, map and fallen suites
  PASS (R2631). **Slice build B2632**: B:\Contractoruilds\contractor-2026-10-26-020703-B2632-fallen-slice-a-1c5b622b.
- **Phase B, 2026-10-26 ~02:55**: the building system (claude/survival-building) and the RPG layer (claude/survival-rpg)
  MERGED; building + survival + rpg PASS (R2641). The people lane MERGED 2026-10-26 ~03:20 (below); next a
  phase B slice build, then the settlement's work and the council (survival_building.md 5-7) and phase C.
- **Phase B people built on `claude/survival-people`** (survival_people.md sections 1-6 and 8: the Person
  record, moods and breaks, lone survivors, hiring by wants, companions with CompanionAI, the talk menu, grief,
  graves, the rise, the take-over): R2645 FLAKY (fallenpeople PASS, survival flaked once on a melee block check, passed the rerun); see survival_people.md's "Where the build is".
- **Phase B's settlement work and council (first form) built 2026-10-26 on `claude/survival-settlement`** (R2649 PASS (settlement, survival, fallenpeople, building)): `Settlement`
  (stocks, beds, defence, footprint, morale, settlers' schedules and meals), `SettlementJobs` (twelve jobs), `WorkOrders`
  (orders and the planning view), `Council` (votes, factions, standing; `Council.server_put` for the world lane's demands),
  `SettlementScreen` ([), waiting (call 136) and solo pause (call 138); see survival_building.md's "Where the build is".
- Known orange: survival's "the dead's bite winds up" flakes on first runs (R2627/R2629/R2631 rerun passes); the
  check now prints why.

### (earlier) 2026-10-26 ~01:00 CDT

Branch `claude/survival` (worktree `B:\Contractor\.claude\worktrees\survival`), dev (37ff24ca, v0.7.0) merged in 2026-10-26.
- **Design done 2026-10-25/26:** calls 1-85 below; docs/survival_world.md, survival_building.md, survival_people.md,
  survival_medical.md, survival_rpg.md; the phase plan A-D at the end of this file. Next: phase A, step 1 (the parry bug).
- **S1 done** (182e519f, survival suite R2592 PASS): menu Survival new world / continue, `Survival` autoload
  (world save `survival_<world>`, clock -> DayNight, hunger/thirst via Consumables' water/ration doses, slower
  stamina low, blood loss empty, death drops everything where he fell (no cleanup in survival) + starter kit,
  survivors' kit/needs saved), `SurvivalLevel` (no garrisons/patrols/US/skirmish/bots), HUD Food/Water line.
- **S2 mostly done** (next commit): `ZombieAI` (idle/hear/see/chase/search, walkers + 15% runners, night
  faster and blinder), `Vitals.undead` (head/face kill, else a hit-point pool), `CompoundLevel._make_zombie`
  (grey civilian on every peer via the AI spawner), `Survival._populate` (spawn out of view 45-75 m by site
  density, despawn past 110 m, kills thin a 64 m cell, refill 2 days), shots wake the dead (Soldier ->
  `Survival.server_noise`). Tested OK: spawning, hearing, chase + bite, headshot, pool, thinning.
- **S2b melee core** `scripts/survival/melee.gd`: telegraphed attacks (windup), dodge/sidestep i-frames,
  block (20% through, stamina, heavy breaks it), parry (block within 0.25 s of landing: stagger + 1.2 s
  counter window, counter instant x2). Zombie bites go through it. Tested OK: windup, held block, dodge.
- **S2b melee weapons built 2026-10-26** (calls 86-89): `MeleeWeapons` (nine weapon items with a `melee` stat,
  light/heavy profiles, the head rule in Vitals.undead), `MeleeInput` (fire/hold/aim/double-tap, V shove, Ctrl
  silent kill), `Soldier._server_melee`, `VoxelArt._melee` models; survival suite's "Melee weapons" section.
  **Step 3 the stealth model and step 4 S3 (ZoneDead crowd, zone pressure, local hordes, the four specials)
  built 2026-10-26**; step 5 the metabolism on claude/survival-metabolism (an Opus lane). **Step 6 (the cold open,
  permadeath, the New world screen with the goal and world options) built 2026-10-26.** Step 8's `fallen` perf suite built (R2623 PASS: a survival night at 22 ms a frame). Next: merge the lanes, a build, then phase B.
- **Step 5 the metabolism built 2026-10-26 on `claude/survival-metabolism`** (R2630 survival PASS at fab17f63): `Needs`
  (calories, water, macros, vitamins, sleep, warmth, wet, hygiene, sickness; S1's hunger/thirst derived), food values on
  items + dirty water, raw meat, beans, dysentery by water quality, `SurvivalSleep` (`Survival.server_sleep`, x12), the HUD's
  low-only signs and `BodyReadout` (backslash); see CHANGELOG.
- **Phase B's RPG layer (first form) built 2026-10-26 on `claude/survival-rpg`** (R2634 rpg + survival PASS at 39231fd8): `Rpg`
  (twelve lines, XP curve, perks, backgrounds + flaws, gates), `Crafting` (essentials), `CharacterScreen` (]); see survival_rpg.md's top block.
- **Step 7 the map (first form) built 2026-10-26 on `claude/survival-map`** (R2622, R2626 at 61e1ab91: map PASS, the
  survival suite's map section all ok; its other fails were the base's melee/stealth ones b2e9038f fixed):
  `SurvivalMap` (explored 64 m cells, known zones, marks that age and fade past 3 days, the safehouse)
  and `FallenMap` (one map, the world grid zooming into the zone). Merged into claude/survival 2026-10-26. Later: real-map relief/roads, intel layers.
- **Phase B's free building built 2026-10-26 on `claude/survival-building`** (R2638: building and survival suites PASS): blocks on the 0.5 m grid
  in six materials and shapes, pieces with key and code locks, real load and span with cracks and falls, blueprints, upgrade
  in place, build mode on 6; see docs/survival_building.md's "Where the build is" and CHANGELOG.
- **(closed 2026-10-26) OPEN BUG:** survival_test's parry check failed: the bite lands ("melee_winding" gone) but the
  parry branch isn't taken and the player isn't hurt, so `Melee._land` most likely found no target at land time
  (`target_in_front` null: the player may move or turn in the windup; the test's zombie has process disabled).
  Print `target_in_front(attacker)` in `_land`, then fix (maybe lock the victim at windup start and re-check reach).
- **Then:** regression suites on the S2 tree (R2593 ran mid-edit: loot/medical results void; smoke, world and
  levelswitch passed), commit/push, then player melee: melee weapons as weapon items tagged "melee"
  (sidearm one-handed: knife, machete, crowbar; primary two-handed: bat, axe, sledge), MeleeInput (fire = light,
  hold = heavy, aim = block/parry, dodge key + direction, sidestep), owner -> host RPCs; then S3 crowd/hordes,
  S4 survivors/companions, S5 crossings, S6 abandoned look, S7.

**Status:** design 2026-10-25, building on `claude/survival`. The Captain's calls (2026-10-25,
asked with the question tool) are in **Calls**; everything marked Proposed is a default to tune.

The Captain's direction (2026-10-25): "open world persistent zombie survival mode", from the main
menu, "players and there should be companions you can meet out in the world and hire for money,
an item or something else", and on the world: "reuse a lot of our zones with some assets edits to
make it more like an abandoned world". Scope: "design doc then more than a slice, much more".

Inspired by DayZ's persistence and scavenging, 7 Days to Die's hordes and nights, and Project
Zomboid's needs, built our own way on Contractor's zones, bodies and squad AI.

## Calls

| # | Call | Decided |
|---|---|---|
| 1 | Where | Standalone, the main menu's **Survival** section; never touches the campaign. Co-op joins as today. |
| 2 | Who | Players, plus **companions met out in the world**, each hired for **money, an item or a favour**. |
| 3 | Zombies | **Mixed**: mostly slow walkers in groups and hordes, some runners, tougher specials later; worse at night. |
| 4 | Death | **Respawn, lose your kit**: your body and everything on it stay where you fell; the world goes on. |
| 5 | World | **Our zones, made to look abandoned**: overgrowth, wrecks, litter, boarded and broken buildings, no lights. |
| 6 | Scope | Design first, then the whole mode in phases (S1-S7), not a one-zone slice. |
| 7 | Goal (2026-10-25 brainstorm) | **Three world goals, chosen at New world:** Reach the evac (a far-side evac point or a radio to repair; arriving with your people alive wins the world), Sandbox (no win: the safehouse and roster are the score), Clear the map (the hardest: every zone's dead thinned under a threshold and held). |
| 8 | Safehouse | **Free building** in the voxel world: walls, barricades, furniture and utilities placed anywhere from scavenged materials (not fixed upgrade tiers). |
| 9 | Noise | **Loud guns punish**: unsuppressed fire reliably pulls the street and can raise a horde; melee, bows, suppressors and distractions are the main tools. |
| 10 | Infection | **Players and companions from the start**: a bite starts a fever clock; antibiotics hold it; **a cure must be reachable** so any player has a reasonable chance to save their character (tied to the RPG layer, call 11). |
| 11 | RPG layer | **Experience and progression** for each survivor (XP, levels, skills); design to come (docs/survival_rpg.md). |
| 12 | Building system | **Voxel blocks + snapped pieces**, to build anything within reason and go past the DayZ base-building mods: material blocks placed and removed in the world grid (wood, scrap, sandbags/HESCO, concrete, steel) for any shape, snapped pieces for doors, hatches, windows, stairs, ladders, furniture, lights, workbench, well; structural integrity (unsupported spans fall; zombies chew wood, metal holds); blueprint mode (ghost pieces built by players or companions); repair, dismantle, upgrade in place; everything a physics object saved with the zone's voxel edits. Design in docs/survival_building.md. |
| 13 | Death (refines 4) | **Permadeath character**: a dead survivor is gone, body and kit stay where they fell; the player starts a **new survivor from zero** (no XP or skills carried over). |
| 14 | Metabolism | **Calories, water, protein/carbs/fat and a few vitamins** on a body screen (inspired by SCUM, less spreadsheet), plus fatigue/sleep, body temperature with wet clothes and wind, carried weight, hygiene; every deficit feeds the medical system (healing rate, stamina, sickness) rather than standing alone. Survival depth past today's survival games; medical depth past SCUM (wound infection staging, sepsis, antibiotic courses, field surgery, fever, blood types and transfusions, hypothermia and heat stroke, bones that heal over days, companion medics). Design in docs/survival_medical.md. |
| 15 | Cure | **Both**: a rare cure serum in hospitals and labs, and a quest chain that makes one reliably (a doctor companion or your own medical skill, a hospital or lab zone, equipment, an immune survivor's blood); antibiotics and rest buy days. |
| 16 | RPG shape | **Learn by doing + perk picks**: skill lines (medical, building, melee, firearms, archery, scavenging, mechanics, driving, cooking, fieldcraft, fitness, stealth) level from use; total XP gives a survivor level with a few general perk picks. |
| 17 | Character creation | **Blank slate by default, or background + flaws**: a background starts one line higher; flaws are taken for points that buy other skills higher (inspired by Project Zomboid's traits). |
| 18 | Companions level | **Yes, by doing**: companions earn XP in what they do beside you; their skills show when you talk to them. |
| 19 | Specials (first cut) | **Screamer** (calls a horde), **Crawler** (under cars, in grass, grabs legs), **Bloater** (bursts, taints the room: masks or distance), **Hazmat** (hard shell: the head or heavy hits). |
| 20 | Living world | **A truly living world, inspired by STALKER's A-Life, big scope**: groups of the living form dynamically with their own objectives and goals (settle, raid, trade, flee, hunt, hold ground), move between zones, fight the dead and each other, and leave traces whether or not a player is there. Design in docs/survival_world.md. |
| 21 | World sim depth | **Full world sim**: every group simulated everywhere on a slow clock (journeys, fights, supplies, deaths resolved by rules while far; live near players). **Groups judge cost against reward** before acting: a raid, a move, a fight or a trade is weighed by its likely gain, losses, noise and the relations it burns, so factions are aware of consequences. |
| 22 | Hordes | **Local and pressure-driven, never world enders**: a zone carries a noise/pressure level (shots, fights, lights, generators, crowds); the local dead drift to it, and only when the pressure peaks does a horde form in that zone. Hordes don't march in from other maps on gunfire alone; a big fight elsewhere raises that zone's pressure, not yours. (Refines S3.) |
| 23 | Settlement | **Yes, from the safehouse**: the base can grow into a settlement; survivors ask to join, the player sets jobs (farm, guard, scavenge, medic, build), it trades and gets raided. |
| 24 | Enclave + groups | A **military enclave** exists, **ambiguous**: the evac, a trap or both by seed and rumour. First-cut group kinds: **settlers, raiders, scavenger crews, cultists** (plus lone survivors as the companion pool, and the enclave). |
| 25 | Offline world | **Frozen with a bounded catch-up on return**: the clock stops when the host quits; Continue runs the world sim up to CATCH_UP_DAYS (Proposed 2) world days (groups move, trades, a raid or two resolve, cells refill) and shows a short "while you were away" report; nothing catastrophic offline (the player settlement can't fall). |
| 26 | Trade | **Barter on a value scale AND cash**, like STALKER and Fallout: every item has a value (ammo, meds, food, fuel weigh most), traders at settlements and roaming scavengers swap, prices moved by what their group needs; found cash is a real currency traders take too. Groups trade with each other on the same rules in the world sim. |
| 27 | Players | **Co-op up to 8, no PvP**: one roster of players plus companions, friendly fire real; raiders and cultists are the human threat. |
| 28 | Settlement depth | **Full politics**: jobs (farm, guard, scavenge, medic, build, cook), stocks (food, water, fuel, defence), morale (theft, desertion, a split), raids and hordes by pressure, recruits drawn by a doctor or stock, size by beds and food (Proposed 24); plus factions inside the settlement, a council or leader challenge, relations with other settlements (alliances, feuds). |
| 29 | The dead's senses | **Hard stealth model**: sight (40 m day, 15 m night, half crouched/prone, blocked by cover and heavy rain), sound (shots 180 m, door kick 60 m, running 25 m, generators and vehicles steadily), smell (blood on you or a fresh kill, 30 m downwind); each zombie has a visible awareness state (idle, suspicious, alert, chasing); sound rings on the HUD when you make noise; crouch-walking past a sleeping horde is a real play. A lone walker is beatable, one bite is a bleeding wound plus the fever clock; numbers, noise and grabs kill. |
| 30 | Time and seasons | **2-hour world days** (a night is an expedition; crops take sessions) and **four seasons over ~40 world days**: winter freezes crops and water, cold the top killer, the dead slower; summer rots food fast; rain soaks and masks sound, fog cuts sight, wind moves smell. |
| 31 | Vehicles | **Rare, earned, loud, plus horses and bicycles**: every vehicle starts a wreck (battery, fuel, tyre, belt; mechanic skill or companion); fuel siphoned and found, runs out; a running truck is fast cargo and roster transport that raises pressure where it goes and can be stolen or stripped. **Bicycles** (quiet, towns, no fuel) and **horses** (farms, feed, spook; fieldcraft skill) are the quiet middle tier. |
| 32 | Map and regions | **~24 typed zones on the region grid** (rural farms with the safehouse, villages, towns, a city, hospital, military base, lab, dam/power plant, port; enclave and evac candidates at the far edges; the cure chain's places by seed), **organized into geographic regions**: desert zones together in a desert region, coastal zones on or within 1-2 tiles of the coast, mountains and hills in their own regions, plains, etc. **Plan for ~48 zones with wilderness** (forests, hills, a river valley: few dead, groups travel, hunt and camp) as the next step. |
| 33 | Stealth UI | **Diegetic first, HUD second**: the zombie shows it (head turn and sniff when suspicious, groan and straightening when alert, scream and lurch when chasing); the HUD adds a small noise ring sized by how far a sound carried and a faint eye icon when something has line of sight; companions call it out. |
| 34 | Seasons' demands | **All four**: winter (temperature falls fast, layered clothes found or sewn, fire or stove and stocked firewood, melt snow, crops stop, the dead slow but linger near warmth); summer (rot without cold store or canning, faster thirst, faster dead, wildfires, worse bloaters); planting and harvest windows (miss it and the settlement starves, seeds are loot, groups raid for stores before winter); season-driven group behaviour (settlers stock up, raiders strike in autumn, scavengers to cities in spring, enclave patrols change, rumours say who moves). |
| 35 | Mounts | **Horses, bicycles and horse-drawn carts**: players ride; companions ride when there are mounts, else walk and keep up; a horse carries packs, needs feed and water, spooks at shots and the dead, can bolt; a bike is silent and fast on roads; a cart is the settlement's early logistics and a mobile stash. **A horse can be tied at a position and a companion left to guard it** (an order). World-sim groups use the same mounts. |
| 36 | Regions in play | **Regions set look, loot and the dead AND are faction territories**: desert (water scarce, heat, open sightlines, few dead, military and port loot), coast (fishing, boats later, fog, salt rot), hills and mountains (cold, caves, mines, dams, hard travel, raider camps), plains (farms, villages, most settlers); each region tends to a dominant group kind others contest (the enclave the port, raiders the hills, settlers the plains), a political shape the living world shifts. |
| 37 | Real maps | **The world map and the zone map read like actual maps**: a real map of the whole world (regions, zones, roads, rivers, coast, relief) that zooms continuously into the zone you're in (streets, buildings, your marks), one map, not two screens; map knowledge grows as you explore and from found maps, notes and rumours. |
| 38 | Weapons | **Ammo scarce, guns common-ish, melee deep**: guns turn up (homes, police, military base) but ammo is the real loot (a box of 20 is a find, calibres matter, reloading from components a late skill); melee off the S2 core (light and heavy swings, shove, parry, stamina, weight and reach: knife, bat, machete, axe, spear, crowbar, sledge; durability; silent kills from behind on an unaware zombie); bows and crossbows the quiet ranged tier with recoverable arrows; suppressors rare and wearing out. |
| 39 | Building cost | **Materials + tools + time, real integrity, plus weather**: materials from trees, stripped buildings, wrecks, sand and cloth, bags and water, beams; a tool in hand; build time per block that skill shortens; companions build blueprints; each material has strength and max unsupported span, overloaded blocks crack then fall as real voxel destruction; zombies chew wood, metal resists, concrete near-immune; dismantling returns part; **weather wear**: wood rots in rain without a roof, snow load collapses weak roofs, metal rusts by the coast; the settlement needs maintenance jobs. |
| 40 | Companions as people | **Needs and safety on their own, work on orders, AND real-people autonomy**: they eat, drink, sleep, patch light wounds, take cover, fight back and call threats unasked; they also loot nearby, pick up ammo and food, barricade a door at night, suggest plans, and can disagree or refuse a bad order. **Emotions and moods like RimWorld** that affect them: fear, grief, hunger, exhaustion, boredom, friendships and grudges, a breakdown or desertion at the bottom, loyalty and courage at the top; moods feed the settlement's politics (call 28). Design in docs/survival_people.md. |
| 41 | First hour | **Cold open at the safehouse, guided by the world**: wake at the farm with the starter kit, a note from whoever was here, a map with the nearest village marked; the first companion candidate within a kilometre with a simple want; the first night in about an hour with a small local pressure; no popups (journal, barks, the note teach); a separate Survival basics tutorial off the menu. |
| 42 | Food sources | **All four**: hunting and trapping (deer, boar, rabbits, birds on the animal layer; bows and quiet rifles, snares, tracking; butchering, spoilage, hides; blood draws the dead; wolves and feral dogs in the hills), fishing (rods and nets on coast, rivers, the dam; boats later; smoking preserves), farming and foraging (seeds, beds, crops by season, watering and weeding as jobs, a greenhouse block for winter; berries, mushrooms some poisonous, herbs), livestock (chickens, goats, cows penned and fed; eggs, milk, meat; they need water and draw the dead). |
| 43 | Crafting | **Essentials and maintenance, plus improvised weapons and armour**: bandages, splints, torches, filters, smoked and canned food, arrows and bolts, spears and clubs, repairs, reloaded ammo late, settlement fixtures; pipe guns, nail bombs, molotovs, improvised armour, a leaf-spring crossbow. **Improvised firearms are unreliable**: more jams, misfires, wear and the odd blow-up than found guns. Recipes gated by skill lines and workbench tier. |
| 44 | Goal modes | **Same world, different win and pressure curve**: Reach the evac (an evac or enclave at a far edge, rumours lead there, pressure rises over the season; win arriving with the roster alive); Sandbox (no evac, local and seasonal pressure; score = days, settlement, roster); Clear the map (no evac, faster refill, specials spread, a zone held only by a standing presence; win when every zone is quiet). Picked at New world, shown on the map. |
| 45 | Information | **Full intel layer**: a journal (people, places, wants, deadlines), rumours from anyone (true, half-true or lies by teller), a repaired radio (group chatter, enclave broadcasts in range), a map that shows only what's explored or told with marks that age, companions reporting; plus a **map table at the settlement** (the C-lane map HUD reused) showing scouts' and allied settlements' reports in near real time, trade routes and known group movements. |
| 46 | Infection clock | **Days-long clock with stages, real choices, plus an immunity roll**: a hidden incubation (half a world day), then fever (stamina down, thirst up), delirium (vision and aim worsen, companions worry), collapse over 3-4 world days; antibiotics pause it a day per course, rest and good food slow it, a doctor's care more; the serum cures before collapse; a companion on the clock can be sent away, treated or put down and the settlement's morale reacts; at collapse a player dies and turns, their body a zombie in their kit. A small chance (fitness and fieldcraft raise it) that a survivor is **naturally immune**; immune survivors are the cure chain's key ingredient. |
| 47 | Sleep | **Fatigue bar, sleep passes time, risk while asleep**: fatigue drains over a world day (faster carrying and fighting); low fatigue slows stamina return, shakes aim, dulls senses; a bed (or a worse bedroll) passes world time at speed for everyone asleep while the host's world ticks, so a watch rotation matters (companions on watch wake you); sleeping outdoors in winter is a cold risk. |
| 48 | Water and hygiene | **Full water system plus hygiene**: bottles, running taps in some buildings, wells, rivers, lakes, rain barrels, snow; raw water carries a dysentery chance by source; boiling, filters and tablets treat it; a well or filter tower is a build goal; the desert makes water the planning problem. **Hygiene**: washing lowers wound infection risk, dirty clothes draw flies and the dead by smell, a winter bath is a cold risk, soap is loot. |
| 49 | World options | **All four at New world**: dead density and speed (density per zone type, night speed, share of runners and specials); loot scarcity (roll chance, refill, ammo weight); needs and medical harshness (metabolism rates, infection clock, serum rarity, cold and heat); living world intensity (group count, raider aggression, settlement growth and fall rate, enclave patrols). |
| 50 | Build order | **Core loop first, then the living world**: Phase A = finish S2 (zombies, melee, stealth senses and awareness states), S3 (crowd, local pressure hordes), the full metabolism, the cold open, permadeath. Phase B = voxel building with integrity, settlement jobs and stocks, companions as people (needs, moods), the RPG lines. Phase C = the world sim (groups, goals, cost/reward, regions as territories, catch-up), trade, the intel layer, real maps. Phase D = seasons, mounts, water and hygiene, the infection chain, settlement politics, specials, improvised weapons. Each phase ends playable and tested. |
| 51 | Co-op death | **Both, the player picks**: a new survivor (background, flaws) entering at the settlement as a newcomer or at the nearest zone edge with a starter kit, the old body and kit left on the map, old companions grieving (a grave if buried) and treating the newcomer as a stranger until trust grows; or **take over a willing companion** (mood and loyalty allowing), their skills and kit now the player's, the roster one smaller. |
| 52 | Group life | **Fully emergent, no bounds**: groups form when lone survivors or a split meet near shelter and food; the leader's personality sets the kind; splits on broken morale or two leaders disagreeing; death at zero supplies and members; no caps, the world can empty or crowd by seed; perf guards (virtual far groups, a live cap near players) rather than design caps. |
| 53 | Using the dead | **All four**: lures and distractions (bottles, car alarms, a radio left playing, a flare, a tied goat; draw a horde onto a raider camp), traps and defences (spike pits, wire that holds walkers, bear traps, drawbridge, kill corridor; piles smell and breed bloaters), masking (gore smeared to mask smell for a while at a hygiene and infection cost; slow among walkers at night; fieldcraft + stealth), bodies as resources and hazards (what they wore, rot that sickens the air, burning draws others, burying a settlement job). |
| 54 | Dialogue | **A contextual talk menu built from their state**: want, what they know (rumours by their travels), trade, recruit, ask about a place or person, threaten, give; lines written per group kind and mood, voiced with the TTS barks; no branching scripts, everything from the sim. |
| 55 | Raids and sieges | **Telegraphed, judged, winnable or bribable, plus horde sieges**: a raider group judges the settlement (defences its scouts saw, guards, stock, reputation) against its need; scouts can be spotted, rumours warn of a build-up; a demand comes first (a share of stores, a person) to meet, refuse or ambush; the attack uses the tactics AI and the dead it draws; losing = stores taken, people hurt or captive (a rescue goal), damage, not a wipe. **Horde sieges**: when the zone's pressure peaks on the settlement the dead come in waves for a night; fence, kill corridor and watch rotation are the whole game; raiders may hit during or after. |
| 56 | Enclave arc | **A real faction with a price**: a military remnant holding the port or the base (fuel, meds, a radio) broadcasting a real but rationed evac; entry costs something (the cure recipe, an escorted convoy, a settlement handed over, your best people conscripted); patrols shoot looters, trade with trusted settlements, officers disagree; by seed honest, corrupt or collapsing, told by rumours and scouting; helping, infiltrating or breaking it are all routes to the evac. |
| 57 | Hostiles | **By reputation and judgement, never scripted hate**: every group's opinion of you comes from what you did where its people could see or hear of it; raiders rob the weak and avoid the strong; cultists convert or capture the lone and feed captives to a horde they keep; scavengers trade unless cheated; all can be talked to, bribed, allied or fought, all judge cost against reward; no group is hostile by default to a stranger. |
| 58 | Body UI | **A body figure with layers, plain-language readouts, gated by diagnosis skill**: a rotatable figure with toggled layers (wounds, bones, infection, temperature, wetness), each part in words first and numbers on hover, a metabolism panel (calories, water, macros, vitamins as rings with trends), treatments dragged onto the part; the same screen on a companion or casualty; **what you can see is gated hard by medical skill** (a novice: "hurt, bleeding"; a doctor: everything; a companion doctor reads it for you). |
| 59 | Settlement work | **Stocks, jobs, work orders, hauling, plus a council**: stocks in stashes and piles; work orders (build blueprints, farm beds, cut wood, smoke meat); people assigned to jobs, hauling, building and crafting on their own schedule with sleep and meals; a planning view of what's short and who's idle (inspired by RimWorld's colony loop, kept first-person); **big decisions go to a council vote** your standing sways (take in a group, pay a demand, move the settlement); a leader challenge if morale and standing fall. |
| 60 | Infrastructure | **All four**: power (generators loud on fuel, solar and batteries quiet and scarce, a wind turbine; lights, fridge, radio, electric fence, tools; a lit settlement is found sooner), water works (repair a town's tower or pump house so taps run; well, rain barrels, filter tower), the dam or power plant (a late crew-and-days project powering a zone, every group's eye on it, the enclave may want it), roads and bridges (clear wrecks, repair or blow a bridge, crossings as chokepoints). |
| 61 | Name | **Contractor: Fallen**: the main menu's Survival section, its own save list, New world screen (goal, options, character creation); shares the game's systems, never the campaign's saves or progression. |
| 62 | Lore and tone | **Grounded and recent, with a hidden antagonist**: the fall was months ago (food on shelves, the enclave has fuel, people remember names); tone quiet and human, the dead a weather you live with. The cause unravels over time: **not the military itself but an organization tied to it, an internal R&D branch, a mix of the CIA and the CDC** (its own name, logo, sites), the mysterious antagonist whose notes, broadcasts, labs and **bunkers** (sealed, stocked, trapped: the best loot and the best player stories) reveal the story piece by piece; the enclave is entangled with it without being it. |
| 63 | Sound | **Diegetic plus a dynamic tension layer**: no combat music; wind, rain, distant groans, generators, your own breathing; silence is information (birds stop); music only at the settlement (a found radio, a companion's guitar) and a few moments; a near-subliminal tension layer (low drones, heartbeat) driven by the stealth model's awareness states. |
| 64 | Start | **A plains farm at the map's quiet edge, with a random element every time**: low dead, a village and a town in reach, settlers near, water close; the city, the hills' raiders, the desert, the coast's enclave deeper in; difficulty grows with distance, the evac on the far side. Each start rolls something different: who left the note and what they left, which neighbour is first met (a settler, a scavenger, a wounded stranger), a wreck or a bunker door nearby, the weather and season of day one, a small early problem (a well gone bad, a walker in the barn, a raider scout watching). |
| 65 | Design docs | **Five docs, world first**: docs/survival_world.md (sim, groups, regions, hordes, enclave and the R&D antagonist, trade, intel, maps, bunkers), survival_building.md (blocks, pieces, integrity, weather, settlement work, infrastructure), survival_people.md (companions as people, moods, dialogue, hiring, politics, co-op death), survival_medical.md (metabolism, wounds, infection, sleep, water, hygiene, seasons on the body, body UI), survival_rpg.md (skills, perks, backgrounds and flaws, crafting); then this file becomes the index with the calls and the phase plan rewritten as A-D. |
| 66 | Antagonist | **ARCHE** ("Applied Research and Containment, Health and Epidemics"): a dry civil-service name, a quiet blue-and-grey seal, clean numbered over-engineered bunkers and relay stations, people who wrote in acronyms; a CDC that answered to the intelligence side. |
| 67 | Catch-up bounds | **Up to 2 world days, companions safe**: pending raids on the settlement become a demand on return; nothing of yours is lost offline. |
| 68 | Joining the enclave | **Yes, as a path with a cost**: serve it (patrols, escorts, tolls on settlements you may know) to earn the evac; standing with others suffers, companions with a conscience may leave, what you learn inside feeds the trail. |
| 69 | Wilderness zones | **After phase D**: ship the 24-zone world complete first; wilderness as the expansion. |
| 70 | Build grid | **0.5 m blocks** (5 voxels a side) with halves, slabs, ramps, wedges, pillars, arches; finer work through slabs and pieces. |
| 71 | Integrity | **Real load with cracks and a warning**: load and capacity per block, the ghost coloured by load before placing, cracking ~20 s before a fall; collapses are real voxel destruction and can kill. |
| 72 | Ownership | **Who holds the place owns it**: no claim markers or locked ground; a group that drives you out takes your builds and you can take theirs; locks with keys or codes keep strangers out. |
| 73 | Wear | **Slow wear, a maintenance job fixes it**: roofless wood rots in ~20 wet days, salt rust ~30 days, a weak roof fails under one heavy snow; a settler on the maintain job repairs from stock, or you do. |
| 74 | Relationships | **Friendships, grudges and families, AND romance and new families**: friendships and grudges from time, fights, slights and gifts; families as met vote and grieve together; couples form over time (moodlets, a shared bunk, jealousy, breakups); children can be born in a long world and need care for years of world time. |
| 75 | Mood breaks | **The full set, rare, trait-driven**: crying fit, rage, binge, hiding, desertion, refusal; needs mood under 20 for hours and rolls by traits; desertion takes some kit and makes a lone survivor with or without a grudge. |
| 76 | Voice | **TTS lines by tags (chatty when safe, quiet when sneaking) with subtitles until recorded; a bigger, better TTS model will replace the current one** (the game can afford more RAM). |
| 77 | Companion death | **Body and kit stay, grief until buried or burned (a burial mechanic), AND a companion killed by the dead rises** as a zombie in their kit; putting them down is its own moodlet; a group or the dead may reach the kit first. Emergent and dynamic. |
| 78 | Metabolism rates | **Realistic rates, generous warning**: ~1,800 kcal and 2.5 l a world day (two real meals and a few drinks per 2-hour day); three days without food before danger, three without water before death; vitamin problems over weeks; warnings well before harm. |
| 79 | Surgery | **The full set, skill-gated with tools and a place, now** (remove fragments, debride, stitch, set bones, drain, amputate; a surgical kit or improvised at a penalty; light, a clean surface, time; anaesthesia); **permanent consequences planned for later** (crooked bones, a limp, amputations changing what a survivor can do, scars). |
| 80 | Fever clock | **A world week** from bite to collapse: time to run the whole chain; the fever a slow shadow over the week rather than a race. |
| 81 | Sicknesses | **All four families**: dysentery and food poisoning; colds, flu and pneumonia (spread in a settlement, a cough is noise); tetanus and gangrene; deficiency illnesses (scurvy, rickets, anaemia). |
| 82 | XP pace | **Faster early, slow late**: lines 1-4 in a few real hours (a new survivor is useful fast), 5-10 a season each; survivor levels quick early, slowing. |
| 83 | Perks | **One per survivor level, permanent, ~20 to choose from**, a few needing a line level. |
| 84 | Creation numbers | **Background +3/+1, flaws worth 1-3 points, ~15 of each**; a 3-flaw survivor can start one line at 5; blank slate stays available. |
| 85 | Top crafting | **Reloads, suppressors, antibiotics and the serum at the top of their lines, plus gunsmithing**: repairing and assembling real guns from parts at firearms 8-9 on a gunsmith bench; gun parts become loot; ceramic plates never crafted. |
| 86 | Melee controls | **Both**: with a melee weapon up, fire = light swing, hold = heavy, aim = block (raised just before a hit = parry), double-tap a direction = sidestep/dodge, use key behind an unaware zombie = silent kill; **plus a quick melee key (V)** for a rifle butt or knife stab while a gun is held (a weak, loud-ish shove that buys a second). |
| 87 | Melee weapons | **All four groups**: one-handed (sidearm slot: knife, machete, hatchet, crowbar, pipe; fast, 1.2-1.5 m; knife silent-kills and skins, machete cuts, hatchet chops and cuts wood, crowbar pries and is blunt, pipe improvised), two-handed (primary slot: bat, axe, sledge, spear; slow heavies, 1.8-2.4 m; bat and sledge blunt with knockdowns, axe cuts and fells, spear holds at reach and thrusts for the head), **shields and off-hand** (a riot shield or door panel: a block that holds without the timing, slower; a sidearm fires over it), **throwables** (bottles, bricks, a thrown knife; bottle = noise at a spot, brick = a stagger; the grenade throw reused). |
| 88 | Melee lethality | **Head kills, body wears, numbers overwhelm**: a heavy to the head drops a walker in one, a light in two or three; body hits take the pool slowly (a stagger, not a kill); runners outpace a heavy (parry and counter or a light to the face); three on you is block-and-back-off or death; stamina the real limit (six heavies and you're gasping). |
| 89 | Silent kill | **Behind an unaware zombie (idle or suspicious), a blade, melee 4 or a knife at any level**: the use key, a 2 s grab-and-stab, little noise; fails and makes noise if the zombie turns in time or another sees you. |
| 90 | Noise-and-light footprint | **Added 2026-10-26**: the settlement's nightly profile (lamps, fires, generators, cooking smoke) as a visible radius on the map table; blackout discipline matters (phase C/D; feeds zone pressure). |
| 91 | Weather fronts + barometer | **Added**: fronts seen coming on the horizon; a found barometer item; storms mask you, fog blinds both sides (phase D with seasons). |
| 92 | Trip-line alarms | **Added**: tin-can lines, flare trips, bells as cheap pieces that warn the watch with a direction (phase B building pieces + the stealth model). |
| 93 | Vehicles as mobile bases | **Added**: a truck or bus fortified with the block system becomes a rolling safehouse (stash, bunk, mounted light); the world sim treats it as a place that moves (phase C). |
| 94 | Dogs | **Added**: a found dog companion with its own senses and needs: warns of the dead and strangers, tracks, hunts small game, barks and draws the dead (phase B/C people). |
| 95 | Radio as a living feed | **Added**: timed broadcasts from groups and ARCHE's numbers station become quests and the trail with no quest giver (phase C intel layer). |
| 96 | Preserving and the larder | **Added**: salting, smoking, canning, a root cellar block; visible and smellable spoilage; food as a seasonal plan (phase D with the metabolism's spoilage). |
| 97 | Scars and a story page | **Added**: every wound, bite survived, kill and companion lost on one page per survivor, readable at a grave; weight for permadeath and the takeover (phase B RPG/character screen). |
| 98 | Landmarks and wayfinding | **Added**: named hills, towers and masts on the real map; companions navigate by them ("meet at the water tower"); getting lost in fog is real (phase C maps). |
| 99 | Contaminated zones | **Added**: ARCHE sites with a taint meter: masks and suits, limited time inside, the best loot behind it; a home for the hazmat kind (phase C/D). |
| 100 | Predators and animals that react | **Added 2026-10-26**: wolves and feral dog packs in the hills, a bear in deep woods, raccoons at stores; every animal flees the dead and the dead chase animals (a running herd is a tell); animal corpses draw the dead by smell (phase C fauna). |
| 101 | Crows, flies, rats | **Added 2026-10-26**: crows circle bodies and fresh kills (a far tell), flies thicken on the unburied (sickness, smell), rats in cities and in a settlement with open stores (food loss, disease); cats as rat control (phase C/D). |
| 102 | Infected animals | **Added 2026-10-26**: dogs and wolves can turn: fast, low, hard to hear; a bitten dog of yours is the companion's hard choice; the cause stays ARCHE's mystery (phase C). |
| 103 | Seasonal migration, fishing species | **Added 2026-10-26**: game moves with the seasons (deer to the valleys in winter, birds gone), fish by water body and season; a hunter's calendar from fieldcraft (phase D). |
| 104 | Regrowth over time | **Added 2026-10-26**: grass through asphalt, ivy up walls, saplings in yards, roads narrowing over the months of a world; towns look more abandoned the longer it runs; walked paths at the settlement stay clear (phase C/D world look). |
| 105 | Wild edibles, medicine, poison by season | **Added 2026-10-26**: berries in summer, mushrooms in autumn, nettles and wild garlic in spring; willow bark, yarrow, honey as medicine; nightshade and death cap as poison; a field guide item and fieldcraft decide what you can tell apart (phase D). |
| 106 | Trees as a resource with species | **Added 2026-10-26**: oak hard and slow to fell, pine quick, fruit trees and orchards, hedgerows; felling makes noise and leaves stumps; woods regrow over seasons; firewood that needs seasoning (phase B/D). |
| 107 | Fire that spreads | **Added 2026-10-26**: dry grass and forest burn in summer, wood builds and wooden houses catch, smoke draws the dead and groups; molotovs and campfires are real risks; a burning zombie keeps walking; rain and firebreaks stop it (phase D). |
| 108 | Water as terrain | **Added 2026-10-26**: swimming and drowning under load, wet clothes, rivers as barriers the dead walk into and sink in (they walk the bottom and climb out downstream), ice in winter that holds or breaks, boats on the coast later (phase C/D). |
| 109 | Light and batteries | **Added 2026-10-26**: flashlights, headlamps, lanterns, candles, chemlights with a battery and fuel economy; light draws the dead and groups; moon phases set how dark a night is; NVG batteries scarce (phase B/C). |
| 110 | Sound propagation | **Added 2026-10-26**: walls and doors muffle, wind carries sound downwind, rain covers it; indoors shots are heard less far; a bell or siren carries for kilometres (phase C with the stealth model). |
| 111 | Barricading and breaking in | **Added 2026-10-26**: board up existing windows and doors with planks and nails, chain gates, lockpick and pry; the dead batter doors and boards down over time (the watch hears it), raiders breach (phase B building). |
| 112 | Decay stages of the dead | **Added 2026-10-26**: fresh ones (weeks) faster and stronger; months on slower, softer, falling apart, but more of them; the world's date sets the mix; a zombie's look says its age (phase C). |
| 113 | Frozen in winter, the spring thaw | **Added 2026-10-26**: hard frost slows the dead to a crawl and freezes the ones left outdoors solid (safe to pass, breakable); the thaw wakes them all at once: the spring horde is the season's set piece (phase D). |
| 114 | The dead wear what they were | **Added 2026-10-26**: a soldier zombie has a rifle and plates (the hazmat kind is one), a doctor's bag on a doctor, a cop with a pistol; loot by who they were and a tell for what a place was (phase C). |
| 115 | Nests and roosts | **Added 2026-10-26**: the dead gather in dark places by day (basements, parking garages, churches) and come out at dusk; a quiet town by day is a trap at night; clearing a nest is a job with a payoff (phase C). |
| 116 | A nerve meter | **Added 2026-10-26**: hordes, a bite, a friend's death, nights without sleep shake the player's nerve: hands shake, hearing rings, the tension layer swells; settles with sleep, safety, a companion's talk, a drink or a smoke (phase D with the medical layer). |
| 117 | Cannibalism as a last resort | **Added 2026-10-26**: human meat is food that costs nerve and standing, risks a prion-like sickness, marks you to groups that learn of it; cultists and the desperate do it; a dark line (phase D). |
| 118 | Addictions and withdrawal | **Added 2026-10-26**: painkillers, alcohol, tobacco, stimulants: real relief with a habit that grows; withdrawal a sickness; the smoker and drinker flaws are the starting cases (phase D). |
| 119 | Dreams and the journal's voice | **Added 2026-10-26**: sleep brings short dream lines coloured by the day; the journal writes in the survivor's voice shaped by traits (phase B/D, cheap). |
| 120 | Weapon wear, jams, cleaning | **Added 2026-10-26**: guns and melee wear with use and weather; a dirty gun jams (clear it under pressure), a cleaning kit and oil restore it; blades dull, a whetstone; a worn axe is slower (phase D). |
| 121 | Ammo condition | **Added 2026-10-26**: found ammo can be corroded or wet (misfires), reloads worse; a tell on inspection with firearms skill; dry storage in the settlement matters (phase D). |
| 122 | Clothing wear and repair | **Added 2026-10-26**: clothes tear and soak, boots wear out (feet suffer), needle and thread fix them; camouflage by colour against the terrain for the living's sight (phase D). |
| 123 | Vehicle wear | **Added 2026-10-26**: parts wear, tyres puncture, fuel goes stale over months; the mechanic's work is a routine (phase C/D). |
| 124 | World events | **Added 2026-10-26**: a supply drop from the enclave every group races for, a convoy on the MSR, a downed helicopter, a church bell rung as a lure (cultists or you), a burning town on the horizon, a storm that takes a bridge out; the sim rolls them and the rumour layer tells you (phase C). |
| 125 | Loot that shows its state | **Added 2026-10-26**: containers look picked-over once searched, hidden caches with clues, locked ones that need a key or a pry, stock that refills only where people pass (phase B/C). |
| 126 | Drop-in co-op and a shared journal | **Added 2026-10-26**: a friend joins a running world as a newcomer at the farm or beside you; the journal and map are shared; companions remember who did what; leaving players' survivors sleep at the safehouse (phase B/C). |
| 127 | A mod kit for Fallen | **Added 2026-10-26**: zombie kinds, items, recipes, perks, backgrounds, lines, group kinds and goals as data files with a documented schema; a world's seed and options exportable; data-first as the RTS plan (ongoing; a docs/fallen_modding.md at phase C). |
| 128 | Children in the world | **Added 2026-10-26**: kids among settlers and lone survivors from the start: can't fight, need care, change every moodlet and vote around them, a reason groups settle; never harmed on screen (phase C people). |
| 129 | Faith and funerals | **Added 2026-10-26**: a pious companion asks for words at a grave, settlements keep a chapel, cultists' faith is the dark mirror; small rites that move morale (phase D politics). |
| 130 | Letters and legacy | **Added 2026-10-26**: a survivor writes a letter kept in the journal and found on the body; the newcomer reads the dead one's letters; a world keeps a lineage of survivors on one page (phase B with the scars page). |
| 131 | One stealth model for the living too | **Added 2026-10-26**: raiders, settlers and the enclave see, hear and smell with the same cone, noise rings and awareness states as the dead; sneaking past a camp works the same way; their guards are better at it than walkers (phase C). |
| 132 | Clothing slots and layers | **Added 2026-10-26**: head, face, torso (base, mid, outer), hands, legs, feet, plus the carrier and pack; layers set warmth, wetness, noise (a rain jacket rustles), camouflage and pockets; found clothes as loot that matters (phase B/D). |
| 133 | Companions use the loadout editor | **Added 2026-10-26**: give and take gear with the 3D loadout editor on a companion, saved kits applied to them, their needs shown beside it (phase B people). |
| 134 | The 3D loadout editor takes pouches and pockets | **Added 2026-10-26**: **the Captain's addition**: the editor also puts items INTO pouches, backpack pockets and clothing pockets (not only the slots and MOLLE points), for the player and companions (phase B UI). |
| 135 | Third-person option | **Added 2026-10-26**: a toggle to third person on foot (as the vehicle camera), aiming first person; melee and stealth unchanged (phase B/C). |
| 136 | Wait and pass time | **Added 2026-10-26**: at a safe spot (the safehouse, a held building) wait an hour or until dusk or dawn, the world ticking at speed as sleep does, interrupted if something comes (phase B with sleep). |
| 137 | Starting season and world size options | **Added 2026-10-26**: New world adds the season you wake in (spring default) and the world size (24 zones now, 48 with wilderness later) (phase D seasons; the size with the wilderness). |
| 138 | Solo pause, co-op never | **Added 2026-10-26**: a world hosted with nobody joined pauses on the menu; with anyone joined it never does (phase B). |
| 139 | Saves | **Declined 2026-10-26**: ironman (one save, no reloads) NOT taken; a world autosaves as today and the save rules stay as they are (a world list on Continue still worth having). |
| 140 | Climbing rules for the dead | **Added 2026-10-26**: walkers can't climb or jump (a 1 m wall or a ladder stops them; they pile until the pile is a ramp); runners vault waist-high; crawlers squeeze under and through gaps; walls, platforms and roofs are real safety (phase B/C). |
| 141 | Builds and the navmesh | **Added**: a requirement on the building lane: placed blocks and pieces update the navigation the dead and the living use within a second; the dead path round or push on them, never through; companions path over stairs and ladders (phase B follow-up). |
| 142 | Accessibility and readability | **Added**: colour-blind-safe HUD tells (the ring, the eye, load colours with shapes), scalable text, a toggle for the tension audio, subtitles for every bark; checked at the 10 resolutions as the rest of the UI (phase D UI pass). Save migration across builds NOT taken now. |

## Already in the code to build on

| Piece | Where | What it gives survival |
|---|---|---|
| Zones from a definition, linked | `ZoneDef`, `ZoneLevel`, `RegionMap.links`, crossings (`Extraction`, `BaseHub.server_cross_on`) | The open world: the campaign's region map, every zone joined to its neighbours at the edges |
| Per-zone saves | `GameState` (`looted`, `dropped`, `voxel_edits`, `bodies`, `vehicles`), `save_zone` | A zone you leave keeps what happened in it |
| A whole world's save | `Campaign` sections under a `campaign_id` | The survival world's own save (`survival_<world>`), never the campaign's |
| Hosting a zone from the menu | `Menu.host_forest_zone` (test zones) | The pattern for New world / Continue |
| Bodies, wounds, ragdolls, gore | `Soldier`, `Vitals`, `BodyDeform`, `Ragdoll` | Zombies and survivors are Soldier bodies near players |
| A cheap crowd | `ZoneAnimals` (MultiMesh, one host packet, hit areas) | The far tier of a horde |
| Sleep and virtual groups | `DynamicSim`, `Virtualizer` | What's far stays cheap |
| Noise | `PeopleLayer.server_noise`, `Alert.server_noise` (every shot, kicked doors) | What draws zombies |
| Food and water | `Consumables` (MRE, IRP, bottled water, ...: "hunger and thirst deferred") | The needs' items: eating and drinking now matter |
| Loot | `data/loot_tables.json`, `WorldValuables`, rarity boxes, compound loot | What there is to find |
| Hiring and the squad | `Hiring.candidate`, `Roster`, `SquadAI`, orders, the 8-slot squad | A recruited survivor is a squadmate |
| Day and night | `DayNight` (hour, weather) | Nights are when they come |

## The build order: phases A-D (call 50)

The design is in five docs; this file is the index and the calls. Each phase ends playable,
tested (its suites green locally and on CI) and merged into this branch; the branch stays off
dev until the Captain says (call: "needs to stay here for now").

| Phase | What lands | Docs | Suites |
|---|---|---|---|
| **A: the core loop** | S1 as built (mode, world save, needs, safehouse, starter kit, HUD) kept; **S2 finished** (ZombieAI, Vitals.undead, melee core; the open parry bug first); **the stealth model** (sight, sound, smell, awareness states, the noise ring and eye icon, the tension layer's hooks); **S3** (the crowd tier, zone pressure, local hordes, the four specials); **the metabolism** (calories, water, protein/carbs/fat, vitamins, sleep, warmth, hygiene; food items' values; raw and dirty water); **player melee weapons and inputs**; **the cold open** with its random element; **permadeath** and the new survivor (blank slate); the real **zoomable map** (world to zone) in its first form; **world options** at New world. | survival_medical.md §1, §4, §5; survival_world.md §5, §12; survival.md | survival (extended), a perfcases "fallen night" case |
| **B: building, settlement, people, RPG** | **Voxel-block building** (grid, shapes, pieces, materials, tools, time, blueprints, integrity, upgrade, dismantle, the build mode); **the settlement** (stocks, jobs, work orders, hauling, schedules, beds; the council's first form); **companions as people** (Person records, traits, needs, moodlets, breaks, autonomy, the contextual talk menu, hiring by wants, graves, the rise); **the RPG layer** (lines, XP, levels, perks, backgrounds and flaws, the character screen, crafting essentials and improvised weapons, the gates); **S5 crossings and persistence** for builds and people. | survival_building.md, survival_people.md, survival_rpg.md | building, people, rpg, survival |
| **C: the living world** | **WorldSim** (groups, people everywhere, the far tick, the judgement, goals, far fights, forming/splitting/dying, the trickle); **regions as territories**; **the dead as pressure across the map**; **the enclave**; **ARCHE and the trail, bunkers**; **trade** (barter + cash); **the intel layer** (rumours, journal, radio, aging marks, the map table); **the catch-up**; **the goal modes**; **S6's abandoned look** across every zone type; **mounts** (horses, bikes, carts, tie-and-guard). | survival_world.md | worldsim, survival, perfcases "settlement night" |
| **D: depth** | **Seasons** (the clock, winter/summer/harvest, group behaviour by season); **the infection chain** (stages, the week, antibiotics, the serum and the chain, immunity); **wound infection, surgery, sicknesses**; **water works and hygiene**; **settlement politics** (factions, council votes, leader challenge, relations between settlements); **raids and horde sieges** against builds; **infrastructure** (power, water works, the dam, roads and bridges); **relationships** (romance, families, children); **top-end crafting** (reloads, suppressors, antibiotics, gunsmithing); **the tension audio layer** and the bigger TTS model; **traps, lures, masking**. | survival_medical.md §2, §3, §6; survival_building.md §7-§9; survival_people.md §9; survival_world.md §6-§8 | all of the above, extended |
| **After D** | Wilderness zones (the 48-zone plan, call 69); permanent surgical consequences (call 79); boats on the coast. | | |

### Phase A, in order (next)

1. The parry bug in survival_test (S2b), then regression suites on the S2 tree, commit.
2. Player melee weapons and inputs (S2b's plan: weapon items tagged "melee", MeleeInput, RPCs).
3. The stealth model on ZombieAI: senses, awareness states, the HUD ring and eye.
4. S3: ZoneDead crowd tier, zone pressure, local hordes, specials.
5. The metabolism on Vitals; food item values; sleep; warmth; water quality; the body screen's
   first form (the figure can wait: rings and words first).
6. The cold open (the note, the neighbour, the nearby thing, the first night), permadeath and
   the new survivor (blank slate), world options.
7. The map: one zoomable map, world to zone, known areas only.
8. A perfcases case; CI green; a build off the branch for the Captain to play.

## Performance

Live zombies are AI soldiers: LIVE_CAP keeps them under the fight case's AI count (32). Their
brain is lighter than SquadAI (no tactics, no cover search): one sight check and one path every
THINK_S (Proposed 0.4 s), less when far. The crowd costs what animals cost. `DynamicSim` sleeps
the rest. Each doc has its own performance section; the budgets meet in perfcases.

## Tests

`survival` suite (S1's checks stand): the menu's New world hosts the safehouse with the
starter kit; needs drain and eating fills them; a zombie hears a shot, walks to it, sees, chases
and bites; a headshot kills it, body shots take the pool; death respawns as a new survivor with
the body left where it fell; a survivor's want is met and he joins; a crossing saves the zone
and the world and Continue puts it back. Each doc lists its phase's suite.
