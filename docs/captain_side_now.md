# Captain's side: what we're working on (2026-10-13)

For cghath and cghath's agent. Kept up to date as pieces land. Newest at the top of the log.

**Ground rule today:** cghath owns the 26 findings in the three-part audit (A1-01 to A3-10).
Captain's side stays out of those areas: saves and campaign, loot-all and the aid bag, reload,
IV sites, the medical menu's row limit, launcher slot controls, pack drag and AI pack recovery,
the scavenge command, corpse extraction, clear-area bonus, civilian blast accounting, building
caches, streamed-out proxies, vehicle repair reach, numeric doctrine profiles, the import-error
verdict, CI logs and `tools/make_build.sh`. If something below needs one of those files, we'll
ask here first.

Captain's side checks GitHub every 15 minutes. If you push a README or note saying what you're
picking up next, we'll read it and steer around it.

## HANDOFF for cghath (2026-10-13, late; Captain's side out of usage). Start here.

**State.** `dev` = 4888efa (loot fix, friendly-muzzle fix, settings menu). Everything newer is on
branches, all pushed:
- **`integrate/b3` = 5862988**: dev + menu cleanup (no people checkbox, people always on),
  settings polish (opaque panel, objective-marker toggle), pouch overhang fix, objective helper +
  ammo readout (mags + "about half" estimate, not exact counts), contract board keeps the mouse
  (base screen steps aside under it). Local suites green (R0360 on b2; R0363 supports). CI was
  running at handoff; one CI flake seen (supports host) that passes locally. **Next: if CI is
  green, ff `dev` to 5862988, then build** (`tools/make_build.sh`, preset renamed "Windows Desktop",
  template `C:/Users/noahg/Downloads/godot.windows.template_release.x86_64.exe/...`) into
  `B:\Contractor\builds`, move B0357 to `builds\outdated`.
- **`ui/gear-marker` = ec22a34** (off 5862988): dead player's "X's gear" label ~35% smaller
  (pixel_size 0.0015 -> 0.00098). One line; merge after b3.
- **Agent branches, may be WIP** (each off 5862988; read the last commit message for what's left):
  - `gameplay/gun-handling` (worktree B:\Contractor-guns, port 25333): sight picture when aiming,
    M110 scope with magnification, realistic spread (M4 spread_deg 1.2 = ~2 m at 100 m is far too
    wide) with sway/recoil/movement as the main error. Must NOT make the AI more accurate.
  - `vehicles/chase-camera` (B:\Contractor-vehcam, 25331): 1st person + 3rd person toggle in vehicles.
  - `vehicles/interiors` (B:\Contractor-vehint, 25332): simple readable interiors and windows.
  Each needs: finish, screenshots checked, its suites + smoke, CI, then merge into an integrate branch.

**Playtest P0362 (build B0357, Captain) findings still open:**
- **Close-range hostile accuracy too high**: squad and Player 1 killed by head/neck shots at 2-6 m
  by village guards and R1 (5 deaths in ~4 min). Look after the guns branch lands (same area).
- **3.42 s hitch on deploying to Harbour yard** (0:10:01): HVT + 12 civilians (town_4 x5) spawn
  plus town stamping the same second, 5 nav rebakes. Spread civilian/garrison spawns over frames.
- Perf line says "memory 0 MB" in release builds (needs a release-safe memory reading).
- AT4 "No room" is expected (launcher slot + pack top only).

**Not ours, left alone:** `B:\Contractor-hotzone` (fix/loot-flake) has 4 uncommitted files
(ragdoll.gd +78, CLAUDE.md, two tests) from an earlier session; not committed by us.
`docs/captain-side-status` local branch has diverged from origin (16 ahead / 4 behind); not pushed.

**Captain decisions still pending:** city building height, wave 6 calls, back utility points,
village houses, base hub -> FOB, CI audit option (Claude PR review vs static checks).

## For you (cghath)

- **Your audit branch is merged into dev (8333679, Captain's go, 2026-10-13 ~20:00).** dev now
  holds all of `fix/audit-2026-10-13` plus Captain's side (ranges, debug tools, buildings, towns,
  Old Quarter, phase 3). CI 28/28 green; local full suite green (R0325 + R0327 squad, R0328/R0329
  casualty). **Please base new work on dev** (`git fetch && git rebase origin/dev`, or a fresh
  branch from it). The four conflicts were the same three test flakes we both fixed (bearer
  re-lift, squad contact race, roles callout): your versions kept, our `_laid` flag removed.
- Known CI flake seen once on the merge: casualty "and rests on the first" (the second ragdoll slid
  off the first: 0.08 m above it; locally 0.22-0.96 m). Passed on the rerun.
- Build helper: `tools/make_build.sh` exports with the preset "Windows Desktop"; the local
  `export_presets.cfg` here names it "Windows" (copied under your name for the build).

- **New audit follow-ups for you** in `docs/audits/followups.md` on `fix/audit-2026-10-13`
  (67ada7b, linked from SUMMARY.md): F-01 the building scan sees one floor (multi-storey
  buildings' upper floors and roofs), F-02 town garrison posts all on the ground floor, F-03
  doctrine `engage_m` below the new sight ranges.

- **Campaign files touched, small and on purpose (towns in zones, Captain's call):** please merge
  dev before you edit these. Every change routes a generated town's type ("town#<seed>") to the
  base type "town" through `ZoneModules.base()`; nothing else changes for the other types.
  - `scripts/campaign/missions.gd`: `module()` gives a town its own civilians and sites;
    `zones()` lists "town" (not "town#<seed>").
  - `scripts/campaign/contracts_gen.gd`: one line in `mission_target`, the module-type filter.
  - `scripts/campaign/radio_chatter.gd`: a "Town" callsign.
  - `data/contracts.json`: a "town" module entry; town in hvt_capture, hostage_rescue and
    intel_grab; Harbour yard holds a town; the new zone `city_hot` ("Old Quarter").
  - Raids play in towns too (on `world/building-storeys`): a town's weapons cache is a crate
    stack in the police armoury or a store room. That's the objective cache, not the AI's
    building-scan cache (A3-04, yours): `scripts/ai/buildings.gd` is untouched (F-01).
- **`scripts/world/voxel_world.gd`** (phase 3, not on dev yet): base structures are stamped at
  most 4 ms a frame instead of all in one frame (a town is 1,100+ boxes).
- **I touched your `tests/aav_test.gd`** (30842cc): "the gunner fires the M2" waited for three
  rounds, but one .50 to the chest can put the dummy down, the gunner stops, and the wait timed
  out (R0284 1 round; CI 2 rounds). It now waits for three rounds or the kill. Revert if you'd rather.
- **`tools/run_tests.sh` hands out the same run number twice** when two runs start in the same
  second (R0232 is two runs): the counter's read-add-write has no lock (SessionLog._next_number
  shares the counter). Not fixed here: the runner is on your audit list (A3-08/A3-09). A
  `mkdir`-based lock round the read and write would do.
- Dev flakes fixed on the way (in integrate/oct13): squad "Alpha is in contact" (waited render
  frames, contact is taken on physics ticks); roles "held-back Moving!" (the team leader's tactic
  call took its place; the test now uses two squadmates who aren't team leaders).

## Today's list, in order

| # | Work | Branch | Files it touches | State |
|---|---|---|---|---|
| 1 | Spotter module: camo from colours (every pattern x preset x civilians), foliage concealment, rifle sights and binoculars past 60 m | `ai/spotting` (d909112) | `scripts/ai/spotting.gd`, `scripts/ai/squad_ai.gd` (`_find_target`), `scripts/world/zone_scatter.gd` (`foliage_between`), `data/items.json` (binoculars magnification), `tests/squad_test.gd`, `FEATURES.md` | Built; R0268 PASS; CI green on d909112 |
| 2 | Casualty flake: "doesn't pick him up again while the order stands" (failed R0257, R0267) | `ai/spotting` | `scripts/ai/squad_ai.gd` (`_care_carry`, `_should_carry`), `tests/casualty_test.gd` | Fixed (c4bb31d): the ragdoll's chest rolled past the 2 m stay radius. Also fixed two CI-only test races on that branch: squad 'Alpha is in contact' (render frames vs physics ticks, also flakes on dev) and roles 'held-back Moving!' |
| 3 | Terrain visual pass: hot-zone roads drawn on the ground | `art/terrain-roads` (30ec617) | new `scripts/world/zone_roads.gd`, `scripts/world/zone_terrain.gd`, `scripts/world/zone_level.gd`, `tests/world_test.gd` | Built, R0270 PASS (world, map) |
| 4 | Gear fit: wire `gear_rig` to the fit helpers in `voxel_art.gd` (male and female) | `art/gear-fit-wire` (ed3494d) | `scripts/combat/gear_rig.gd`, `tests/armor_test.gd` | Built, R0272/R0273 PASS; CI green |
| 5 | Gear secondary motion: bags and armour sway with the body | `art/gear-motion` (6bd3a5a) | new `scripts/combat/gear_sway.gd`, `scripts/combat/gear_rig.gd`, `tests/animations_test.gd` | Built, R0275/R0276 PASS |
| 6 | Tree and bush art pass to match the voxel characters | `art/scatter-art` (6ce346a) | `scripts/world/zone_scatter.gd`, `data/terrain_presets.json` (conifer_share), `docs/terrain_presets.md`, `tests/preset_shots.gd` | Built, R0283 PASS |
| 7 | Final audit and a smoke test of the debug tools (bug-report key, session logs, AI overlay, test-log numbering) | `integrate/oct13` | new `tests/debug_tools_smoke.gd`, `docs/debugging.md` | Smoke test P0292: 12/12 pass; runner check passes; audit done, 4 code fixes in 8f8812a (pack turn sign, sway reset, ordered targets in deep leaves, straps with no carrier) |

## Next (Captain, 2026-10-13), in order

| # | Work | Branch | Files it touches | State |
|---|---|---|---|---|
| 8 | Engagement ranges up: hostiles see 200 m (was 60), the squad 300 m (was 120); aim error at skill 0 1.2 deg (was 2.0); scrub drawn to 400 m and hides nobody past it | `ai/ranges` (ac6957e) | `scripts/ai/squad_ai.gd` (SIGHT_RANGE, SQUAD_SIGHT_RANGE, AIM_UNSKILLED_DEG), `scripts/world/zone_scatter.gd` | On dev. **cghath: doctrine engage_m should match these (audit follow-up F-03).** |
| 9 | Debug tools: overlay shows spotting and alert state; performance lines in session logs; test history page | `debug/overlay-alert` (897eb0e) | `scripts/ui/ai_overlay.gd`, `autoload/session_log.gd`, `tests/session_log_test.gd`, new `tools/test_history.py`, `docs/debugging.md` | Built, R0295 PASS; CI pending |
| 10 | Procedural buildings, phase 1: generated single-storey houses with interior chunks (`docs/building_gen.md`) | `world/building-gen` | new `scripts/world/building_gen.gd`, new `data/building_chunks.json`, `tests/world_test.gd` | Built (R0300 PASS: 40 seeds, every room reachable and furnished, doorways clear); placing them in zones comes with the town module (11) |
| 11 | Procedural buildings, phase 2: shops, warehouse, clinic, police station; a town module (street grid of lots) | `world/building-gen` (57c16fc, aa1228a) | `scripts/world/building_gen.gd`, `data/building_chunks.json` (48 chunks), `scripts/world/zone_modules.gd` ("town#<seed>" type; HALF/POINTS/GARRISON/LOOT now static vars, read the same), `tests/world_test.gd` | On dev. **cghath: zone_modules.gd changed, merge dev before touching it.** |
| 12 | Towns in zones: one village in every hot zone is a town; Harbour yard has one; HVT capture, hostage rescue and intel grab can play in towns | `world/building-gen` (1919ac7) | `scripts/world/zone_def.gd`, `zone_modules.gd`, `building_gen.gd`, `scripts/people/person_look.gd`, campaign files above, `tests/world_test.gd`, `missions_test.gd`, `contracts_test.gd` | On dev; R0311-R0318 PASS |
| 13 | Urban hot zones: "Old Quarter" (`city_hot`), 3-4 towns round the HQ, patrols in their streets | `world/building-gen` (903c235) | `scripts/world/zone_def.gd` (`generate_hot(..., urban)`), `missions.gd`, `data/contracts.json` | On dev; R0317 PASS |
| 14 | Procedural buildings, phase 3: two storeys with stairs, flat roofs the AI can climb onto (parapet, railed hatch), L-shaped buildings, walled yards and courtyards | `world/building-storeys` | `scripts/world/building_gen.gd`, `data/building_chunks.json` (52 chunks: 4 yard), `scripts/world/zone_modules.gd` (a town's own top), `scripts/world/voxel_world.gd` (stamping budget), `tests/world_test.gd` | Built, R0321-R0323 PASS, CI green; screenshots in Discord. Upper floors and roofs are walkable but not garrisoned: audit follow-ups F-01/F-02 for cghath. |
| 15 | Procedural buildings, phase 4: city zones (denser streets, taller buildings) | later | | Queued |

## Decided (Captain, 2026-10-13)

- Towns: in hot zones (in place of a village) and in contract zones, and urban hot zones too.
- Interior chunks vary moderately per placement (an optional item 60% or more, at most 20% smaller).
- Phase 3 (L shapes, courtyards, storeys) approved.
- Enemy camo: stays "urban" for now; decided with factions in wave 6.
- Scrub: drawn further (400 m) rather than capped; it hides nobody past where it's drawn.
- Engagement and detection ranges up (item 8).

## Waiting on Captain

- Procedural buildings: replace the village's hand-built houses, or keep both; how tall in cities.
- Back utility points (A/B/C/D), homeostasis.

## Log

- 2026-10-13 20:00: dev 8333679: cghath's audit fixes merged with Captain's side; playtest build next.

- 2026-10-13 18:55: phase 3 built (storeys, stairs, roofs, L shapes, yards) on `world/building-storeys`; dev 903c235 (towns in zones, Old Quarter).
- 2026-10-13 18:10: procedural houses on dev (c856aaa); shops/warehouses/clinics/police, towns and 48 interiors following.
- 2026-10-13 17:00: ranges up and debug tools (items 8, 9) built; procedural buildings planned (items 10-12).
- 2026-10-13: dev fast-forwarded to 8f8812a on the Captain's go; these notes are on dev now.
- 2026-10-13 06:20: integrate/oct13 8f8812a CI green; waiting on the Captain's go for dev.
- 2026-10-13 05:45: everything on the list built; integrate/oct13 full suite R0284; debug tools smoke P0292 pass; final audit running.
- 2026-10-13 04:50: casualty flake fixed; roads and gear fit built and pushed; starting gear motion.
- 2026-10-13 04:15: list posted.
