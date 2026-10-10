# Build plan: agent waves

**Status:** agreed 2026-10-10, not started. Covers everything still open in
[contractor_handoff.md](contractor_handoff.md). The handoff and the design doc stay the
authority on rules and numbers; this file only says who builds what, in which order.

## How a wave runs

1. **Specs.** Before each wave, Claude (the integrator) writes a spec per workstream:
   the files it owns, the interfaces it must use or provide, and the checks that prove it
   works.
2. **Build.** One Workflow run per wave, up to 5 agents at once. Each agent works in its
   own git worktree on its own branch, runs the smoke test plus the full headless suites
   that cover its area, and adds tests for what it builds.
3. **Review.** A reviewer agent checks each branch against its spec; the builder fixes
   what it finds.
4. **Merge.** The integrator merges the branches, resolves overlaps, runs every suite,
   updates CHANGELOG.md, README.md and the handoff checklist, and makes a test build
   (`tools/make_build.sh`).
5. **Playtest.** The merged wave is pushed to the `dev` branch. Captain playtests from
   `dev`. Fixes go in before the next wave starts; `main` fast-forwards to `dev` once
   Captain okays it.

### Rules for agents

- Edit only the files your workstream owns. If you need a change elsewhere, stop and
  report it instead.
- Don't edit CHANGELOG.md, README.md or the docs; put user-facing notes in your final
  report and the integrator writes them up.
- Don't push. Don't touch `builds/` or `export_presets.cfg`.
- Run `--import` once in a fresh worktree before running tests (Godot's class cache).
- Use the Voxel Tools build: `%USERPROFILE%\Downloads\GodotVoxel_1.7\godot.windows.editor.x86_64.exe`.
- Art belongs to Noah. His asset pack is voxel art generated in code at runtime, the same
  way `scripts/art/voxel_art.gd` builds our soldiers: scripts such as
  `scripts/vehicle_art.gd` fill a Voxel Tools `VoxelBuffer`. It covers characters and gear,
  weapons, environment and vehicles, and mission types. Don't edit art scripts; call them.
  Where Noah's script isn't in the repo yet, use a simple placeholder behind the same kind
  of call so it can be swapped in one place.

## Waves

### Sources

- [contractor_handoff.md](contractor_handoff.md): Captain's decisions and working agreements.
- `docs/contractor_design_doc.md`: the full design with the numbers (blood, bleed rates,
  kit items and times, armor ladder, impact table, supports, missions). It's on Noah's fork
  (`noahgonzalez4506/Contractor-Phase3-Squad`, commit f764bbf) until it reaches this repo.
- Noah's asset repo, `noahgonzalez4506/Contractor-Assets-and-References`: `VehicleArt`
  (`scripts/vehicle_art.gd`), 13 code-built voxel vehicles at 5 cm with paint schemes:
  `uh60`, `ah1z`, `aav7`, `bradley`, `abrams`, `maxxpro`, `matv` and six technicals. API:
  `instance(model, scheme)`, `prop(model, scheme)`, `size_m(model)`, `spin_rotors(node, delta)`.
  Integration is copying the file to `scripts/art/vehicle_art.gd`.
- Still to export from claude.ai: the mission brainstorm doc (needed by wave 4) and the
  Arma mod research doc (useful for waves 1 to 3).
- Keys agreed after the handoff: stance steps on Caps Lock + WASD, interaction on Left Ctrl,
  self-interaction on Left Ctrl + Left Alt, no giving up while downed.

### Wave 0: preparation (integrator, before any agents)

- [x] **Design doc in this repo:** `docs/contractor_design_doc.md`, pushed to main by Noah.
- [x] **Split `scripts/actors/soldier.gd`** into `soldier.gd` (state, spread and recoil,
  carrying, death, host-side requests), `soldier_movement.gd` (Movement node) and
  `player_input.gd` (PlayerInput node). No behaviour change; all suites pass.
- [x] **Wound-model interface** in `vitals.gd` ("Wound-model interface" section), backed by
  HP: `is_unconscious`, `in_cardiac_arrest`, `is_dead`, `blood_fraction`, `pain`, `injury`,
  `seconds_to_death`, `speed_mult`, `sway_mult`, `stamina_mult`, `condition_text`,
  `server_hit(part, hit)`, `server_impact(part, round_class, distance)`, plus replicated
  `net_state`. Hitboxes carry a `body_part` meta; `Ballistics.round_class(weapon)` gives the
  round class. Ballistics, grenades, squad AI, HUD, command menu and dummies use it.
- [x] Create the `dev` branch.

### Wave 1: phase 3 core (5 agents)

**Status:** built and merged on `dev` 2026-10-10 (all nine suites pass); waiting for Captain's playtest.

| # | Workstream | Owns |
|---|---|---|
| W1 | **Wound model:** 6 L of blood with bleeding scaled by heart output; simulated arteries and big veins, body map (brain, heart, lungs, arm and leg bones, tissue, chest cavity); wound channels with cavitation reach (pistol 2 cm, intermediate 5 cm, full-power 7 cm); fractures by round class; pain 0 to 1 with knockout thresholds and wake rolls; blood-loss effects (sway, stamina, speed, vision from 15% lost); unconscious at 40%, cardiac arrest at 50% with the 10-minute window; fragments as 3 to 8 small wounds (grenades switch to this); body-part hitboxes on soldiers and dummies; enemies ignore unconscious foes. Until wave 3 nothing can restart a heart, so arrest ends in death after the window | `vitals.gd` and new wound files, hitbox nodes, body-hit path in `ballistics.gd`, frag damage in `throwables.gd` |
| W2 | **Armor and ballistics:** the design doc's NIJ-named ladder for every round and armor piece; vest tiers (aramid, fragment and spall coverage); plate materials (ceramic crack zones of about 5 cm with -30% stop chance per earlier hit and an integrity that shatters; steel spall unless coated; polyethylene deforms); helmet ratings; the impact table (pain, stagger, winded, concussion chance, rib cracks by range, helmet stops fatal only where real); ACE3 ballistic values so energy and level change with range | `voxel_armor.gd`, armor path in `ballistics.gd`, armor and ammo stats in `items.json` |
| W3 | **Movement and stance:** X crouch, Z prone, Caps Lock + W/S stance steps (three standing and three crouching heights), Caps Lock + A/D side stances, Q/E lean (hold, double-tap to stay), C weapon mount (about half sway and recoil, unmounts on move), F fire mode, momentum (jog in about 0.3 s unloaded, doubled with a heavy load) and settle sway; hitboxes follow stance | movement part of the soldier, `character_model.gd`, movement keys in `controls.gd` |
| W4 | **Interaction menus**, ACE-style: hold Left Ctrl and look at an object, vehicle or person to show action points, radial menu, release to pick; Left Ctrl + Left Alt for your own body and gear (where you read your wounds). Pickup, revive (removed in wave 2), carry, drag and handing gear to a squadmate move into it; E becomes lean | new `scripts/ui/interaction_menu.gd`, input part of the soldier |
| W5 | **Squad structure:** two fire teams of four, one medic each; roles (team leader, medic, autorifleman, grenadier, marksman, rifleman) with starting kits, players pick theirs and AI fills the rest; command menu Target, Mount, Combat mode and Team; AI callouts as subtitles with an audio hook | `squad.gd`, `command_menu.gd`, non-medical parts of `squad_ai.gd`, role kits |

### Wave 2: phase 3 finish (3 agents)

**Status:** built and merged on `dev` 2026-10-10 (all twelve suites pass); waiting for Captain's playtest.
Changed mid-wave on Captain's direction, by two more agents: the stopgap revive is removed
(consciousness follows SpO2, pain, morphine level, blood loss and total trauma; blood creeps
back slowly once every bleed stops, until IV), every dead soldier leaves a body with its gear
on it (saved with the zone), and medics put the wounded first even in a firefight.

Captain's wave 1 playtest fixes, merged on `dev` 2026-10-10 (all 14 suites pass): knockouts,
armor voxels and pickup, world materials, action animations. Still open: **movement feel**
(sliding on ice); branch `fix2/p2-movement` has unfinished, untested work to pick up.

| # | Workstream |
|---|---|
| W6 | **Kit and treatment:** the field items from the design doc's kit table: tourniquet (4 s, 6 s on yourself; rushed placement stops only 70%), pressure bandage, hemostatic gauze, vented chest seal, splint, morphine (overdose risk), NPA airway. The IFAK and trauma kit become containers of these. Treat yourself and others from the W4 menus; `_server_use_medical` uses a real item for every treatment |
| W7 | **AI casualty care on the wound model:** the real care order (under fire: smoke, drag, tourniquet; once safe: airway, seal, splint); medics carry the medic-only items; buddies carry casualties after the leader. Phase 3 passes when squadmates rarely die to bad pathing |
| W8 | **Ammo and kit:** loose rounds and loading magazines; the respawn kit becomes M4, 2 spare mags + 90 loose rounds, 1 smoke, 1 frag; coloured smoke grenades (green, yellow, blue, purple) for the wave 5 supports |

### Wave 3: medical depth (4 agents)

From the design doc: IV (gauges 10 to 20 with flow, placement time, pain and rarity) and IO
access; saline and blood bags (250, 500, 1000 mL); pressure bags; vein collapse from 37%
lost; decompression needle and tension pneumothorax; breathing with per-lung efficiency
and SpO2 (hidden: laboured breathing, greyed vision, pulse oximeter); epinephrine,
morphine, adenosine and atropine with heart rate; CPR and defib (players and medics, only
once volume is back above 60%); surgery kits (2, 3 or 5 uses, about 20 s per clamp,
chest-wound closure with a 10% reopen chance); other damage: overpressure and blast lung,
falls, concussion, burns and burn dressings, hypothermia and blankets, deafness.

Standing rules for this wave (user, 2026-10-10):
- **Remove the stand-in blood recovery** once IV/IO and fluids work: delete
  `WoundModel.BLOOD_RECOVER_PER_MIN` and its line in `advance()`, so blood only comes back
  through IV or IO. Update the tests that rely on it (`_trickle` in `medical_test.gd`, the
  slow-recovery checks in `wounds_test.gd`, the README and CHANGELOG lines).
- **No revive, ever.** Don't bring back a revive action, item or API. Epinephrine, CPR and the
  defibrillator act through the wound model (restart the heart, clear a cause of
  unconsciousness); a casualty still comes round only when their body lets them.
- **Epinephrine keeps its wake-up roll** (user, 2026-10-10), as the design doc says, and also
  acts through the body (heart rate, part of CPR). The roll is a chance to come round sooner,
  not a revive: it can't wake someone while a cause still holds (blood loss, low SpO2, pain
  over the threshold, trauma, arrest).

### Wave 4: phase 4, mission loop (5 agents)

- **World scale:** contract zones of 2 to 4 km² and hot zones of 8 to 16 km² (hot-zone size
  being confirmed). Today's voxel world is one bounded box, so this needs terrain plus
  streamed voxel modules (compounds, blocks, outposts) placed on it. The riskiest item in
  the wave; it gets its own spike first.
- **Contracts:** contract board and fixers; MW5-style negotiation (pay vs salvage share vs
  support budget); contract zones and hot zones (several contracts at once, resupply and
  bank loot mid-zone, ends at extraction, lapsed contracts cost reputation); reinforcement
  timer; loot tiers by zone (contract zones up to medium tier).
- **Map and briefing:** a map with a grid overlay; markers (including the dead-player gear
  marker); Arma-style briefing and planning (known enemy positions, plan marks, insertion
  point, supports).
- **People on the map:** civilians (fines, reputation hits, contract voided at 8
  casualties); HVTs (friendly ones cooperate; hostile ones run and resist until
  zip-cuffed; carry them or seat them in a vehicle); intel as physical items that open leads.
- **Campaign state:** cash economy and shop (gear, repairs, medical, support calls); base
  hub (armory, motor pool, medbay); respawn pool per deployment (4 free in a contract zone,
  8 in a hot zone, then bought); roster persistence, permadeath and MIA with recovery
  missions; extraction at a grid or purple smoke with the landing-safety rules.

Mission types come from Noah's pack and the mission brainstorm doc. Rival contractors,
bounty hunters and the heat meter go to wave 6.

### Wave 5: phase 5, vehicles and supports (4 agents)

Noah's `VehicleArt` models go in first. Drivable ground vehicles for players and AI, with
cargo as a rolling stash; vehicle armor immune to small calibre (7.62x54R and up can
penetrate or disable), with damage carving the voxel hulls; anti-armor launchers (AT4,
RPG-7 with PG-7V and OG-7V, Javelin top attack, MAAWS, NLAW, SMAW) by round type (HEAT,
tandem HEAT, HE/HEDP, thermobaric); AAVs from the LHD on the coast or the FOB inland,
commandable; Blackhawk resupply (grid or green/yellow smoke), transport (hot zones,
green/blue smoke, loiters until marked, first call takes green) and extraction (grid or
purple smoke, lands within 100 m of an unsafe spot); support calls with cost and cooldown;
aircraft and AAVs lost with their cargo and passengers. Still open: who fields the AH-1Z,
MRAPs, Bradley and Abrams.

### Wave 6: phase 6, factions

Persistent world (repairs, reoccupation, simulated operations between missions that move
the front and post matching contracts); side locking; reputation tiers and allied troops
in the support menu; allies (USA, Great Britain, Canada) selling gear and vehicles by
reputation; enemy gear by region (Chinese, Russian, Iranian, insurgent); technicals and
light vehicles; rival contractor teams; bounty hunters with a heat meter and named,
Nemesis-style squads. **Before this wave:** Captain decides reputation tiers, allied troop
types and what limits the allied-troop support menu.

### Wave 7: art, world and weapons

The rest of Noah's asset pack as it lands (characters, gear, weapons, environment),
replacing the placeholders, with armor still destructible voxels; day and night, weather,
NVGs as gear; modular weapon attachments (optics, lights, lasers, suppressors, grips);
optional assists for co-op newcomers; controller support.

### Wave 8: player-built faction (design only)

One agent writes a design proposal for the stretch goal, including the campaign-operation
tier the design doc puts under it, for Captain to decide on.

## Risks

| Risk | Mitigation |
|---|---|
| Parallel agents edit the same file | Wave 0 split of `soldier.gd`; file ownership per workstream; integrator merges |
| The wound model touches everything | Wave 0 interface stub: other code calls the interface, W1 changes only what's behind it |
| Missing numbers | The design doc has most; values it marks as proposed stay tunable |
| World scale (km² zones) | A spike before wave 4; zones may start smaller and grow |
| Token cost | Up to 5 agents per wave, one wave at a time, playtest gates in between |
| Windows path length and Godot cache in worktrees | Short worktree paths; `--import` first |
