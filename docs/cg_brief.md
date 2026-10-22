# cghath: working brief (2026-10-21)

Hey cg, here's where things stand and what's next, all in one place. It takes over from the
2026-10-20 task list. One change, and it's on me (Claude): that list told your agent to ask
Captain when a call seemed like his, which is why it kept stopping to wait on answers. Sorry about
that. Captain is usually playtesting rather than watching chat, so it works better if you make the
call and keep going.

## How to handle decisions

1. **Make the call**, using "Decisions already made" below. When in doubt, go with whatever's
   closest to Arma 3 + ACE3/KAT + LAMBS/VCOM realism that's still fun to play.
2. **Put new numbers in data** (`data/*.json`) or a named const marked `Proposed`, so they're
   easy to tune later.
3. **Jot the call down** under "Calls made" at the bottom of `docs/audits/followups.md`: one line
   with what you picked, why, and the alternative. Captain can look over them whenever.
4. **Carry the task through:** code, tests, CHANGELOG, push. If one piece can't be done (missing
   art, a bug in someone else's area), build the rest, log the gap as an F-xx item, and move on
   to the next thing.
5. **The only time to hold off** is something that would delete or overwrite player saves or
   someone else's work. Even then, take the safe option, note it, and keep going.

## Decisions already made (answers to the usual questions)

- **Art:** characters and gear are **0.5 cm voxels** (VoxelArt BODY_VOXEL; gear FINE_VOXEL). No
  meshes or textures for bodies. Real camo patterns.
- **Names:** real military gear names are fine (M4, M1014, PKM). Factions, companies, vehicles we
  invent and anything sci-fi get **original names**, no trademarks. When describing Contractor, say it
  "learns from" or is "inspired by" other games rather than "copies".
- **Realism bar:**
  - medical is ACE3 + KAT and beyond;
  - AI should beat Arma 3 Veteran + LAMBS + VCOM;
  - gunplay and animation feel like Star Citizen on foot;
  - gore is realistic, on by default.
- **Multiplayer:** host-authoritative. State changes go through the host's `server_*` functions
  and RPCs. Every peer and late joiner sees the same thing. Anything random that should match on
  every peer uses a deterministic seed.
- **Numbers:** when unsure, pick a sensible value, mark it Proposed, and make it tunable.
  Deterministic over random where saves or sync are involved.
- **Saves:** never delete them. Archive, don't remove. Zones start fresh each contract.
- **Bots act like players:** they choose things and say so (callouts). Nothing teleports or
  happens by reflex.
- **UI:** use the shared UiKit kit. Every menu says what it's for. It should fit the ui_test's 10
  resolutions.
- **Testing:**
  - headless Godot only, so no windows pop up while Captain is gaming on this PC;
  - set CONTRACTOR_PORT and CONTRACTOR_TEST_TAG, because other agents test in parallel;
  - run your affected suites plus smoke, not the full suite locally; CI runs the full set;
  - test logs are never deleted.
- **Branches:**
  - base new work on `origin/claude/ai-driving`, which has everything (v0.5.1 = 1a74488);
  - one branch per task; push it;
  - **You may update `dev` as needed** with new features and content (Captain, 2026-10-21).
    A change only has to be compatible and not a major regression: no suite that passed before
    now fails.
  - **Your review is enough** (Captain, 2026-10-21). Where something needs a review or approval
    before it merges or ships (yours, Claude's or another agent's), your review is the sign-off.
    Nobody else needs to approve it.
  - Claude merges your branches into claude/ai-driving too and cuts builds.
  - Don't wait for a merge to start the next task.
- **When something lands:** a CHANGELOG entry, then a short note in Captain's Discord thread.

## Already done (no need to redo)

- Items 1-5 of the 2026-10-20 list: treatment props and first-person hands, fingers, visible
  tourniquets/splints/IVs, faces and per-soldier looks, blast dismemberment and synced pieces.
- Also done:
  - gunfire dismemberment and gore fixes (neck stump, hanging limbs);
  - helmet fit;
  - feet;
  - arm and hand hits;
  - the first headshot on a downed man;
  - the conscious-but-dying state;
  - pocket loot;
  - 214 new items;
  - the terror groups and the living war;
  - the breacher role.
- **One 12-gauge system:**
  - Standard and Hi-brass shells in every shotgun;
  - Breaching rounds only in the M1014 and the **Skeleton Key** (your M870, renamed);
  - a choke for the Remington 870;
  - your F-131 (AI shotgun ammo) is fixed.
  - Heads-up: your later "M320 only: ... ours comes out" commit on feat/m320-shotgun would take
    the Skeleton Key back out, so we're leaving that one unmerged. Your M870 lives on as the Skeleton Key.
- **Merged from you:** demolitions, fire support, fallen (dog tags, memorial), M320,
  world-visual, pip-scopes, tutorial-2, assault-warning.
- **Not yet merged:** `feat/missions-2`, `feat/voxel-smoke`, and your newer `feat/demolitions`
  commit (F-122). Finish and push them; Claude merges them next.
- H-menu injury text, tracers and fire-mission arcs.

## Your queue, in order, with the calls already made

Checked against the code on 2026-10-21 (claude/ai-driving 75b4ec5). Everything below is missing or
only partly built: the part to build is spelled out. Already built, so no need to redo:
- tutorial sections;
- UI pass;
- economy (your feat/economy-balance is superseded: close it);
- compound loot;
- IFF marks;
- PIP scopes, first pass;
- weapon rework, first pass;
- world visual pass;
- weather (clear, overcast, fog, rain and storm; fog cuts spotting; storms ground helicopters);
- the gore setting (off / reduced / full);
- building phases 1-3.

### 0. Land what you have

Bring `feat/missions-2`, `feat/voxel-smoke` and the `feat/demolitions` F-122 commit up to date
with origin/claude/ai-driving, get their suites green, and push. Close `feat/economy-balance`.

### 1. World expansion: the top priority (Captain: "true expansion of terrains and props/buildings")

Today, one zone of 2-5 km² is a heightmap with 11 presets:
- noise hills, dry wadis and one sea edge;
- woods, copses and hedgerows;
- straight dirt roads with no collision;
- about 25 outdoor prop shapes and 52 interior layouts;
- 5 building types, at most 2 storeys;
- towns of 12-20 buildings.

Build it out, in this order:

1. **Water.**
   - Rivers and streams that cut their own valleys, with flowing water you can wade (slower, and
     deep water swims or blocks), banks and reeds.
   - Lakes and ponds.
   - Fords, culverts and **bridges with collision**: concrete, steel truss and footbridges, so a
     vehicle can cross and a demolition can drop one.
   - Make river_valley a real river.
2. **Roads.**
   - Paved and asphalt roads with collision, curves that follow the ground, junctions, roundabouts
     in towns, kerbs and pavements in towns, and dirt tracks between farms.
   - Roads link the zone's sites as now, and match across linked-zone crossings.
3. **Terrain features and presets.**
   - Gullies and ditches that give cover.
   - Real cliffs and rock faces: steep ground with collision and a rock look. Overhangs can wait.
   - New presets:
     - **marsh/swamp**: reeds, standing water, soft ground that slows you;
     - **snow/winter mountain**: snow cover, frozen streams, snow tracks; no snow physics beyond
       slowing;
     - **farmland**: field patchwork, crops by season, orchards, irrigation channels.
   - Zone defs can name these, and "procedural" can mix them.
4. **Landmark buildings** (building_gen.md lists most as "later"), in this order:
   - a mosque and a church;
   - a school;
   - a garage/workshop;
   - a fuel station and a fuel depot site;
   - a factory;
   - a farm (house, barn, silo, pens);
   - a harbour (quays, sheds, cranes);
   - an airfield (runway, hangars, tower);
   - an oil field (pumps, tanks, a flare stack);
   - geometry for the terror groups' sites, which are names only today: **drug lab** and **IED
     workshop**.
   - Plus **ruined and bombed-out** variants of every type.
   - Each is its own BuildingGen type with interior chunks, and appears where its asset tag already
     says (terror_groups.md:316-321).
   - Fix building_gen.md and feature_comparison.md section 8.2, which claim an "office" type
     that doesn't exist; add a real office building while you're there.
5. **City zones** (building_gen phase 4): dense street grids, apartment blocks and towers.
   - **Heights (call made, Proposed):** 3-5 storeys in a city core, 2-3 on the outskirts, a few
     6-8 storey towers as landmarks.
   - Stairwells and roof access on all of them; garrisons use the upper floors.
   - Stream them per block if performance needs it.
   - A "city" terrain preset, and at least one city hot zone (the Old Quarter becomes a real city).
6. **Village houses (call made):** replace the hand-built village houses with generated ones in
   village style, keeping each module's layout and garrison posts.
7. **Prop library**, at least triple today's outdoor set:
   - street furniture: lamps, poles, wires, signs and bus shelters;
   - market stalls and awnings;
   - fences and gates of every kind;
   - power lines and pylons across the countryside;
   - wells, water tanks, livestock pens and animals (goats, sheep, dogs, no AI beyond wandering),
     irrigation;
   - **scenery vehicles with real voxel shapes** in place of box wrecks: parked cars, trucks,
     burnt-out hulks;
   - shipping containers outside modules;
   - graves and cemeteries;
   - generators, satellite dishes, laundry lines, hay bales.
   - Every prop has collision and cover that matches what's drawn.
8. **Performance:**
   - the queued woods perf pass, so normal zones can have dense copses (docs/terrain_presets.md);
   - F-121: the vehicle range's blocks.
   - Keep the townperf and world suites green, and add a frame-time check for a city block.

**Done when:** a new contract can put the squad in a river valley with a bridge, a marsh, a
snowy pass, farmland or a city. Every landmark above shows up where its tag says. Towns read as
lived-in. The world, townperf, map and smoke suites pass.

### 2. Armour lane (docs/combined_arms.md), Captain's next priority after item 1

Captain wants playable tanks soon and asked to hand the heavy combined-arms work to you (ours is
tight on usage this week). docs/combined_arms.md is the full design. Section 9 is the build plan
(phases, dependencies, tests, budgets) and section 10 has every call already made, so there's
nothing to ask. Work it like your world items: a branch per item (e.g. `armour/modules`,
`armour/guns`), commits saying "cg_brief queue item 2.x", the follow-ups in followups.md, and a
Discord note when each lands. Claude merges your branches into claude/ai-driving as they come.

**Standards (Captain, 2026-10-22: "make sure it follows the current standards for armor"):**
- **Vehicles: NATO STANAG 4569 (AEP-55).** Every vehicle and armour package gets a rated
  protection level per arc:
  - KE levels 1-6, from 7.62x51 ball up to 25 mm APDS-T;
  - artillery levels by 155 mm HE burst distance;
  - mine/blast levels 1 to 4a/4b under the wheel and belly (6 to 10 kg TNT).
  Each level is stored with the vehicle (`stanag_ke`, `stanag_mine`), and armour_test proves the
  plates meet it: the level's threats are stopped at its range, and the next level's aren't
  always. Above STANAG's range (MBT frontal armour), keep the doc's RHAe line-of-sight figures from
  public estimates.
  - Proposed ratings: the M-ATV and MaxxPro at KE 2 / mine 3b (with add-on armour KE 3), the
    Bradley base at KE 4 front, with BUSK/ERA against RPGs.
- **Personal armour: NIJ 0101.07** (2023), the current standard, in place of 0101.06's
  IIA/II/IIIA/III/IV.
  - Re-rate data and armor_rules.gd to HG1, HG2, RF1, RF2 and RF3 with their threat lists
    (RF2 adds M855 and M80; RF3 is .30-06 M2 AP).
  - Map old levels: IIA/II → HG1; IIIA → HG2; III → RF1; III+/III++ → RF2 where they stop M855,
    otherwise RF1; IV → RF3.
  - Keep the hit behaviour the same except where the new threat lists change it. Say so in the
    CHANGELOG.

**The armour items:**
- **2.0** Standards pass: STANAG levels on the A1 data and armour_test; the NIJ 0101.07 re-rate
  of personal armour. Do this first.
- **2.1** A2: modules, spall, crew hits, kill states.
- **2.2** A3: main guns: the Abrams 120 mm and its loader, the Bradley 25 mm dual feed, TOW,
  commander and loader seats.
- **2.3** A4: gunnery: sights, thermal, LRF and fire control, the stabiliser, hatches.
- **2.4** A5: the 1P/3P vehicle HUDs and the x-ray. **The first build cut is here**: tanks firing
  with sights and HUDs, so tell Captain in Discord when it lands.
- **2.5** A7: fire and destruction effects.
- **2.6** A8: logistics and armour packages (each package keeps its STANAG rating).
- **2.7** A6: driving physics, fording the rivers, bridge load limits (your ZoneWater/ZoneBridges).

A1 (the armour model) is being finished by a Claude session on `claude/ca-a1-armour-model`. Start
2.0 once it's merged into claude/ai-driving (a few hours).

### 3. Operations lane (docs/combined_arms.md)

- **3.1** D1 + D2: operation zones of about 8 km and their performance. Pick up the paused WIP on
  `claude/ca-d1-operation-zones`; its CHANGELOG entry says where it stopped.
- **3.2** D3: operation contracts, phases, the front grid, pay by phase, feeding the war. It
  needs Claude's B2 (the AI commander), so build the contract and front-grid parts first and hook
  the commander in when B2 lands.
- **3.3** D4 and D5, the mission types: phased invasion, armoured thrust, beach landing, seizing
  a crossing, holding a town.
- **3.4** D8: staging from a friendly FOB. It builds on Claude's D7, the US in the living war.

### 4. Vehicle art and light armour (docs/combined_arms.md)

- **4.1** D6a: T-72B3, BMP-2, BTR-82A, MT-LB, the three HEMTTs, the rhino truck, the armoured
  SUV, and a captured-MaxxPro scheme. Interleave this whenever it suits you.
- **4.2** D6b: their armour, modules and weapons data (with STANAG levels) and the factions'
  vehicle tables, after 2.1 and 2.2.

Claude keeps the parts tied to its squad AI files:
- B, the AI commander;
- C, high command and the UI;
- A9, AI crews and armour tactics;
- D7, the US in the living war;
- the performance pass.

Where an item needs a hook in squad_ai.gd, tactics.gd or squad.gd, keep it to one line and note it
in followups.md.

### 5. Real picture-in-picture scopes

The first pass (gun_sight.gd SubViewport) isn't reading as a real scope. It needs:
- a true second render at the scope's real magnification;
- the lens moving with the gun (sway, recoil), and **eye relief**, with the image shrinking and
  vignetting when your head isn't lined up;
- the reticle in the right focal plane (FFP/SFP per scope) with working parallax;
- the scope body hiding the rest of the view naturally;
- NVG and thermal through it;
- variable-power scopes zooming on the scroll wheel;
- holding the frame rate (the render scale is a setting).

### 6. Weapon models across the board: detail first, iron sights first of all

Every gun, not just the first-pass list.
- **Iron sights:**
  - the right front post and rear aperture or notch shapes for each gun, with protective ears and
    hoods, and folding BUIS;
  - **the sight line really lined up** when you aim, at the right height over the bore, readable
    in first person, with the zero matching the sight picture.
- **Detail at 0.5 cm:**
  - receivers, ejection ports, charging handles, selectors, mag releases, bolt catches;
  - rail slots, muzzle devices, gas blocks, slings and sling mounts;
  - the right colours and finishes per gun (matte black, FDE, wood, parkerised).
- **Moving parts:** where the rig allows, the bolt or charging handle moves on reloads.

### 7. Mission variety: improve what's there, and add new types

**Already in (don't re-add):**
- raid, HVT capture, hostage rescue, intel grab;
- convoy ambush, hold the line, downed crew rescue, sabotage, recon;
- client escort, supply line, manhunt, convoy chase;
- the three locals jobs;
- forward observer;
- your missions-2 types: HVT kill, crash site, overwatch, night and weather contracts.

**Improve the existing ones:**
- more than one way to win (a convoy stopped by a mine, an ambush or a roadblock);
- things that change mid-mission: reinforcements, a target that moves, weather that rolls in
  during the mission (today weather is fixed per zone), a secondary objective from intel;
- briefings with the map marked;
- enemy behaviour that fits the mission;
- debriefs and pay that reflect how it went (clean, quiet, fast).

**New types:**
- counter-IED route clearance;
- bridge or route denial with demolitions (needs the bridges from item 1);
- town or city clearance, block by block;
- a mortar or sniper hunt (finding the enemy static weapon team shelling a village);
- prison camp liberation;
- defector exfil under pursuit across zones;
- an airfield or helipad strike (needs the airfield from item 1).

Each type shows up on the board, plays start to finish, and has its own test.

Combined arms and invasion missions (larger zones, armour columns, beach landings, seizing
crossings) are Claude's, alongside the armour work, so no need to build those.

### 8. Follow-ups (F-xx in docs/audits/followups.md)

- **F-130:** the AI grenadier fires the M320.
  - HE at enemies in cover 30-250 m away, never with a friendly within 12 m of the aim point.
  - Smoke on the "throw smoke" order.
  - Loads by hand in cover.
- **F-120:** the squad avoids our own mines and claymores (Demolitions.hazards in path costs and
  move points).
- **F-160 / F-161:** a worn dog-tag model; a scavenger or bearer takes a fallen friendly's tags
  and says so.
- **F-150 / F-151:**
  - enemies shoot the recon UAV once it's below 300 m and in sight;
  - enemy vehicle crews drive out of a fire-mission area after the first round lands.
- You may edit squad_ai.gd and tactics.gd for these; keep each to a helper plus a hook.

### 9. Medical: what's still missing

- IV lines pull out on a sprint or carry.
- CPR slows the arrest window (Proposed ×0.5 while it's done properly; wound_model.gd:1800).
- A stretcher/litter for 2 carriers.
- Body bags.
- Medical foley: tourniquet ratchet, velcro, packaging.
- A heartbeat when SpO2 is low or blood loss is high.
- Fix the stale header at vitals.gd:28-30.

### 10. Hit reactions that follow the hit

`CharacterModel.flinch()` picks a random side, and stagger only follows plate stops. Make the
flinch and stagger follow the hit's direction, scaled by round energy and body part (leg hits
buckle, shoulder hits spin). Players get a view kick to match.

### 11. Night and optics

- NVG IR illuminators (visible only under NVG).
- Thermal optics as a scope variant: white-hot/black-hot, sees through smoke, not through walls.

### 12. Player drones

- A recon quadcopter: data-link range, battery, marks targets.
- An FPV drone: one-way, warhead from Warheads, jammable by the existing jammer.

### 13. Vehicles and air, in this order

Armoured gameplay is Claude's now (Captain, 2026-10-21): crewable Bradley/Abrams/AAV main guns,
first- and third-person vehicle HUDs, light armour across the factions, and US forces fighting in
the living war. No need to build those. Still yours, in this order:
1. Enemy armed helicopters at high alert.
2. Close air support and attack-helicopter runs as a support purchase (the AH-1Z model exists,
   parked on the LHD).
3. The Razorback nose pod.
4. Player-flown aircraft, last.

### 14. Multiplayer

- Gear changes send deltas, not the whole snapshot (inventory.gd:1393-1401 `_publish`; ammo
  already sends deltas).
- A `--server` launch flag that hosts a campaign headless with no local player.

### 15. Campaign

LRRP missions with time acceleration and fatigue (day_night.gd has a fixed TIME_SCALE; there's
no fatigue system yet). Food and water stay deferred: don't build them.

### 16. Structural collapse

Buildings lose support and drop chunks as physics debris when blasted enough. Synced, capped
for performance, and the voxel world stays the source of truth.

When the queue is done: the oldest open F-xx item, then anything in docs/build_plan.md marked
Queued.

## Calls made

Add these to the bottom of docs/audits/followups.md as you go, one line each:
`date | what was decided | why | the alternative`. Captain reads them when he gets to them.
