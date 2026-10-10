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

### Wave 0: preparation (integrator, before any agents)

- **Design doc in the repo:** Noah's Claude exports the design doc (and the Arma mod
  research doc) to `docs/design_doc.md`. Blocks W1, W2, W6 and wave 3.
- **Split `scripts/actors/soldier.gd`** (857 lines) into parts with no behaviour change:
  movement, human input and camera, host-side requests, carrying. Verified by all suites.
- **Wound-model interface stub:** the functions the rest of the game will call on
  `Vitals` (conscious or not, blood, pain, arrest, per-part hits, movement and aim
  penalties), backed by today's HP for now. AI, HUD, dummies and tests switch to it, so
  W1 only changes what's behind it.
- Create the `dev` branch.
- **Asset pack in the repo:** Noah pushes his art scripts (to `dev` or a branch) as they're
  ready, so later waves call them instead of building placeholders. Needed by wave 4
  (mission types) and wave 5 (vehicles) at the latest.

### Wave 1: phase 3 core (5 agents)

| # | Workstream | Owns |
|---|---|---|
| W1 | **Wound model:** 6 L of blood, wounds per body part with bleeding by vessel proximity, pain, unconscious at 40% lost, cardiac arrest at 50% with the 10-minute window; body-part hitboxes on soldiers and dummies; enemies ignore unconscious foes | `vitals.gd` and new wound files, hitbox nodes, body-hit path in `ballistics.gd` |
| W2 | **Armor and ballistics:** NIJ-named rating ladder for rounds and armor; vest, plate and helmet ratings; ceramic crack zones that weaken and shatter; steel spall; plate integrity; impact effects (pain, knockouts, rib cracks by range) through the W1 interface; ammo ballistic values from ACE3 | `voxel_armor.gd`, armor path in `ballistics.gd`, armor and ammo stats in `items.json` |
| W3 | **Movement and stance:** X crouch, Z prone, Caps Lock + W/S stance steps, Caps Lock + A/D side stance, Q/E lean (hold, double-tap to stay), C weapon mount (about half sway and recoil), F fire mode, momentum into starts, stops, turns and stance changes, heavier with load; hitboxes follow stance | movement part of the soldier, `character_model.gd`, movement keys in `controls.gd` |
| W4 | **Interaction menus:** hold Left Ctrl for actions on objects and people, Left Ctrl + Left Alt for yourself; pickup, revive, carry and drag move into it (E becomes lean) | new `scripts/ui/interaction_menu.gd`, input part of the soldier |
| W5 | **Squad structure:** two fire teams of four with a medic each, players pick their role; command menu Target, Mount, Combat mode and Team; AI callouts as subtitles with an audio hook for later voice lines | `squad.gd`, `command_menu.gd`, non-medical parts of `squad_ai.gd` |

### Wave 2: phase 3 finish (3 agents)

| # | Workstream |
|---|---|
| W6 | **Medical items and treatment:** tourniquet, bandage, vented chest seal, splint; IFAK and trauma kit as real kits; treating yourself and others from the W4 menus; `_server_use_medical` uses a real item for every treatment |
| W7 | **AI casualty care on the wound model:** medics and buddies treat with real items, carry or drag by the handoff's rules, dead friendlies carried to exfil |
| W8 | **Ammo and kit:** loose rounds and loading magazines; respawn kit becomes M4, 2 spare mags + 90 loose rounds, 1 smoke, 1 frag |

### Wave 3: medical depth (4 agents)

Fluids (saline and blood in 250/500/1000 mL, IV gauges 10 to 20, IO, pressure bags,
vein collapse at 37% lost); surgery kits with hemostats and chest-wound closure;
epinephrine, morphine, adenosine and atropine; CPR and defib (players and medics only,
volume first); breathing and oxygen with fluid in the lung and collapsed lungs.

### Wave 4: phase 4, mission loop (4 agents)

Contract zones and hot zones (several contracts from one faction, ends at extraction,
lapsed contracts cost a little reputation); zone graph and world map with markers
(including the dead-player gear marker); cash economy and a shop for gear, repairs,
medical supplies and support calls; loot tiers by zone; extraction at a grid coordinate
or purple smoke with the landing-safety rules; roster persistence, permadeath and MIA
with a recovery mission. Mission types come from Noah's pack.

### Wave 5: phase 5, vehicles and supports (4 agents)

Drivable ground vehicles for players and AI; AAVs from the LHD on the coast or the FOB
inland, commandable from the command menu; Blackhawk resupply (pallet at a grid or on
green or yellow smoke) and transport (hot zones, green or blue smoke, loiters until it
sees one, first call takes green); support calls with cost and cooldown; aircraft and
AAVs can be destroyed with their cargo and passengers. Vehicle models come from Noah's
`vehicle_art.gd`; damage can carve its voxel buffers the way armor does.

### Wave 6: phase 6, factions

Territory that shifts between missions, reputation tiers, enemy technicals and light
vehicles. **Before this wave:** Captain decides reputation tiers, allied troop types and
what limits the allied-troop support menu (open in the handoff).

### Wave 7: art, world and weapons

Wiring in the rest of Noah's asset pack: his code-generated characters, gear, weapons
and environment replace the placeholders, with armor still made of destructible voxels
(no file importer is needed, since the pack builds `VoxelBuffer`s in code); day and night, weather, NVGs as gear; modular weapon
attachments (optics, lights, lasers, suppressors, grips); optional assists for co-op
newcomers.

### Wave 8: player-built faction (design only)

One agent writes a design proposal for the stretch goal, for Captain to decide on.

## Risks

| Risk | Mitigation |
|---|---|
| Parallel agents edit the same file | Wave 0 split of `soldier.gd`; file ownership per workstream; integrator merges |
| The wound model touches everything | Wave 0 interface stub: other code calls the interface, W1 changes only what's behind it |
| Missing numbers | Wait for `docs/design_doc.md`; values not in it are marked tunable |
| Token cost | Up to 5 agents per wave, one wave at a time, playtest gates in between |
| Windows path length and Godot cache in worktrees | Short worktree paths; `--import` first |
