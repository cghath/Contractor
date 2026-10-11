# ChrisPlan handoff: everything left, ready to pick up

**For:** Noah (Captain's side) and any agent working with him. **From:** cghath (Chris) and
his agent, 2026-10-11, with `dev` at 7ec6fd0 (all 20 suites passing).

This is cghath's side's plan for the rest of the build, written so any part can be picked up
without asking. The rules and numbers stay in the design doc and
[contractor_handoff.md](contractor_handoff.md); the wave order and agent rules stay in
[build_plan.md](build_plan.md). Wave 4B has its own detailed handoff:
[wave4b_handoff.md](wave4b_handoff.md).

**If you take a wave or a piece of one, mark it in build_plan.md ("Captain's side" with the
date), as with wave 3, so both sides never build the same thing twice.**

## Where things stand

| Wave | State | Notes |
|---|---|---|
| 0 Prep, 1 Phase 3 core, 2 Phase 3 finish | Done, on `dev` | Playtest fixes from Captain's two playtests are in |
| 3 Medical depth | Done by Captain's side | cghath's own wave 3 was dropped (kept on a local branch only); its extras are listed under Backlog |
| 4A Mission loop, first half | Done, on `dev` | World scale, contracts and economy, people, base hub and roster, map/briefing/extraction, one join handshake |
| **4B** Wire the loop, hot zone | **In progress, Captain's side**: part 1 (loop wiring) done | [wave4b_handoff.md](wave4b_handoff.md) |
| 5 Vehicles and supports | Planned below | AH-1Z, MRAPs, Bradley, Abrams: the US and the close allies that operate them (Captain, 2026-10-11) |
| 6 Factions | **Blocked on Captain** | Needs the decisions listed below |
| 7 Art, world and weapons | Systems half planned below | Art waits for Captain's asset scripts; Stormworks-style characters in progress on Captain's side |
| 8 Player-built faction | Design proposal only | |

## How a wave runs (what has worked)

1. **Spec first.** Per workstream: the files it owns, the interfaces it uses or provides
   (exact class and function names), the checks that prove it. Give each workstream its own
   new test suite and its own test tag and port.
2. **Parallel builders in git worktrees**, one branch each, then a **reviewer** per branch
   that reruns every suite, then a **fix** pass only if the reviewer finds blockers or majors.
   Five at once is the ceiling that worked.
3. **Small shared groundwork before the wave** (an interface stub, an autoload, a data
   section) so parallel agents build against the same names. Wave 3's heart-rate stub and
   wave 4's `Campaign` autoload and `map_area()` were enough to keep five branches mergeable.
4. **Merge, then run every suite**, then fix integration bugs. The seams between parts are
   where the real bugs were (4A: two join handshakes fighting; a client's spawn position).
5. **Docs** (CHANGELOG under Unreleased, README controls/tests/known gaps, build_plan status,
   handoff checklist), **a dated build** (`tools/make_build.sh <label> "<what to test>"`),
   then push `dev` as a fast-forward. cghath's side summarises to cghath before every push.

**Gotchas we hit:**
- Usage limits can kill agents mid-run. Branches and worktrees survive. Save uncommitted
  work as a WIP commit and rerun with a "continue in that worktree" note.
- A worktree-isolated agent can't run git in another agent's worktree. Finished work then
  lands on that agent's `worktree-...` branch, so merge from the reported commit.
- Never run two test runs with the same `CONTRACTOR_TEST_TAG` or `CONTRACTOR_PORT`.
- Kill hung headless Godot test processes left by stopped runs before the next full run.
- Bash heredocs mangle Python with backslashes and quotes, so write scripts to a file.
- CI runs the stock Linux Voxel Tools release editor. Verify a red CI suite on the custom
  Windows build too before blaming the engine (the spall check was a real bug).

## Wave 5: vehicles and supports (proposed 4 workstreams)

**Decided (design doc and handoff):**
- Aircraft are AI-flown only. Ground vehicles can be driven by players or AI.
- Vehicle armor is immune to small calibre: 7.62x54R and up penetrate or disable.
- Anti-armor works by round type: HEAT, tandem HEAT, HE/HEDP, thermobaric, top-attack.
- The four player-faction supports:
  - Blackhawk resupply: a grid reference, or green or yellow smoke.
  - Blackhawk transport (hot zones only): a grid or green or blue smoke. With neither, it
    loiters near the players, avoiding fire, until it sees one.
  - AAVs: from the LHD on the coast or the FOB inland, commandable.
  - Blackhawk extraction: a grid or purple smoke, landing near the spot if it's unsafe
    (terrain or obstacles; enemy fire doesn't move it).
- Supports are lost with their cargo and passengers.
- Weather and terrain decide what can fly or drive: storms ground helicopters, and AAVs
  can't work mountains.
- **Who fields the AH-1Z, MRAPs (MaxxPro, M-ATV), Bradley and Abrams (Captain, 2026-10-11):**
  America, and close allies only where they really operate those American exports. In the
  friendly set that is all four for the US; MRAPs for the UK (Mastiff and Ridgback, Cougar
  family) and Canada (Cougar, RG-31); no AH-1Z, Bradley or Abrams for either.

**Art:** Captain's `VehicleArt` from `noahgonzalez4506/Contractor-Assets-and-References`
(`scripts/vehicle_art.gd`, 13 vehicles at 5 cm). Copy it to `scripts/art/vehicle_art.gd`.
API: `instance(model, scheme)`, `prop(model, scheme)`, `size_m(model)`,
`spin_rotors(node, delta, rpm)`, `mesh(model, scheme)`. Models: `uh60`, `ah1z`, `aav7`,
`bradley`, `abrams`, `maxxpro`, `matv`, six technicals. Schemes: army, marine_gray, od,
desert, white, tan, red.

| # | Workstream | Owns | Checks |
|---|---|---|---|
| V1 | **Vehicle core.** A `Vehicle` body on Jolt with seats (driver, passengers, turret where the model has one), enter and exit through the Left Ctrl menu, cargo as a rolling stash (the inventory system, litres and mass), host-authoritative driving with client input, AI drivers following a path, damage: hit zones (engine, wheels or tracks, crew, cargo), hulls carving at 5 cm the way plates do, burning and wrecks saved with the zone | `scripts/vehicles/*`, the vehicle seats and entries in the interaction menu, wrecks in `GameState` | Drive, carry 4, load cargo, take damage; small arms bounce; 7.62x54R penetrates the light ones; a burning vehicle kills its passengers and its cargo; a client drives and a late joiner sees the seats |
| V2 | **Anti-armor.** AT4, RPG-7 (PG-7V, OG-7V), Javelin (top attack, lock-on), MAAWS, NLAW, SMAW as weapons with backblast, by round type against vehicles, structures (voxel blast by material) and infantry (frag, overpressure through the wound model) | weapon and round data in `items.json` and `rounds.json`, `scripts/combat/launchers*.gd` | Each round type against each target class; backblast hurts whoever is behind; Javelin hits the roof |
| V3 | **Helicopter supports.** An AI-flown UH-60 for resupply (lands, drops a pallet), transport (picks up and drops off the squad; hot zones only) and extraction (takes HVTs, loot and deposited items, and the people aboard). Calls by grid reference or smoke of the right colour; loiters until marked; landing-safety search; leaves under heavy fire or is shot down and lost; cost and cooldown through `Economy.server_pay_support`, drawn from the contract's support budget first | `scripts/supports/*`, the command menu's Support entry (0), 4A's `Extraction` (the helicopter becomes extraction's ride) | Each call by grid and by smoke; loiter then land on a seen smoke; an unsafe spot lands within 100 m; a lost helicopter loses its cargo and passengers; cost charged; a client calls one |
| V4 | **AAVs, LHD and FOB.** The LHD offshore on coastal zones, the FOB inland (4A's base hub is the FOB scene); AAVs deploying from them, commandable from the command menu (move, hold, follow, dismount), amphibious on coastal maps; motor pool at the base (4A placeholder) holding the company's vehicles between deployments | `scripts/supports/aav*.gd`, the base motor pool, zone coast or inland flag in `ZoneDef` | An AAV drives in from the LHD, takes orders, carries the squad, swims; the motor pool keeps a damaged vehicle's state |

**Order:** V1 first, or with a vehicle-body stub agreed up front, because V3 and V4 sit on it.
V2 can run beside V1.

## Wave 6: factions (blocked)

**Before this wave, Captain decides:**
1. The reputation tiers: what each tier unlocks.
2. The allied troop types.
3. What limits the allied-troop support menu.
4. How the real-world faction set (being drafted in the vehicle-model thread) replaces the
   repo's three placeholder factions.
5. ~~Who fields the AH-1Z, MRAPs, Bradley and Abrams.~~ Answered: the US and the close allies
   that operate them (see wave 5).

**Scope once decided (design doc):**
- **Persistent world.** Damage is repaired and positions reoccupied over campaign time.
  Factions run simulated operations between missions that move the front and post matching
  contracts.
- **Side locking.** Taking work from one faction locks you out of its enemies' contracts for a
  while.
- **Allies.** Reputation tiers unlock allied troops in the support menu. The USA, Great
  Britain and Canada sell gear and vehicles by reputation.
- **Enemies.**
  - Gear by region: Chinese, Russian, Iranian, insurgent.
  - Technicals and light vehicles, using Captain's technical models.
  - Rival contractor teams.
  - Bounty hunters with a heat meter, and named, Nemesis-style hunter squads that remember the
    squad.

4A's `Economy` already keeps per-faction reputation as plain numbers, ready for tiers.

## Wave 7: art, world and weapons

**Art half (Captain's side).**
- Stormworks-style voxel characters at real scale on the same joints (in progress), then
  gear, weapons and environment from the asset pack.
- Every placeholder sits behind one function so it swaps in one place: `ZoneModule._build_proxy`
  (zone stand-ins), `PersonLook` (civilians and HVTs), the base hub buildings, `ItemIcons`.
- cghath's side doesn't touch `scripts/art/voxel_art.gd` or the soldier's look.

**Systems half (proposed 4 workstreams, any side):**

| # | Workstream | Notes |
|---|---|---|
| S1 | **Day and night, weather** | Time of day per zone, from the contract, and passing during a deployment (LRRP time acceleration later). Sun and moon light; darkness cuts AI spotting. Weather: rain, fog, overcast, storms, affecting sight, sound and AI detection. Storms ground helicopters (wave 5 supports read it). All saved with the zone and replicated |
| S2 | **NVGs and lights** | NVGs as helmet-mounted gear: flip up or down, green image with grain, a battery, a gen/FOV value proposed. IR lasers and illuminators visible only through NVGs. Weapon lights and visible lasers that the AI can see |
| S3 | **Weapon attachments** | Optics (red dot, magnified with a zoom), lights, lasers (visible and IR), suppressors (sound and AI hearing range, flash), grips (recoil, sway). Attachments live in the weapon's item state like its magazine, so they travel with it, save and replicate. Attach and detach in the inventory screen, using Captain's MOLLE-style attach points as the pattern |
| S4 | **Assists and controller** | Optional, off by default, host-set for co-op newcomers: aim slowdown, wound hints, objective markers, a simpler interaction menu. A full gamepad layout for every control, with radial menus on the sticks |
| S5 | **Voxel smoke (CS2-style)** | Captain, 2026-10-11: on the roadmap, "we'll tackle it when it's time". Smoke as a volume on a coarse voxel grid over the world: it spreads from the grenade cell by cell, flows through doors and windows, stops at walls and fills rooms, drifts with the wind and thins out. What a player sees and what blocks AI line of sight follow the real cloud (today: round puff clouds, `SmokeCloud.blocks` a sphere). Blasts push holes in it that refill; gunfire may part it briefly. Replicated as a seed and its events, so late joiners rebuild the same cloud. Coloured smokes keep their colour for the helicopter supports |

## Wave 8: player-built faction (design only)

One agent writes a proposal for Captain: what building your own faction involves, whether it
replaces or sits beside contracts, and the campaign-operation tier (multi-deployment
operations) the design doc puts under it.

## Backlog (small, any time)

**From Captain's playtests and the reviews:**
- You can fire during a pickup or equip animation.
- A dragged casualty eases back about 1 m when put down.
- An equip animation plays even when the action then fails.
- M opens the map over the inventory screen; Tab does nothing while the map is open.
- The inventory screen's Use only matches a task's first-choice item.
- AI squadmates don't load magazines from loose rounds, and role kits carry no loose rounds.
- The voxel edit log is never compacted.
- Every inventory change re-sends the whole inventory snapshot. That's fine on a LAN but needs
  a lighter path before internet play.

**Handoff checklist items still open:**
- Make permadeath on bleed-out apply to AI squadmates only, and MIA when they're left behind
  alive. 4A's base does MIA; check that the rule reads right everywhere.
- Update `docs/squad_design.md` for buddy pairing and the Throw, Carry, Drag and treatment
  intents. They're already in the code.
- AI voice callouts. The audio hook exists: `res://audio/callouts/<id>.ogg`.
- Check that X, Z and C don't clash with any older bindings.

**Docs to export from claude.ai into `docs/`:**
- ~~The mission brainstorm doc~~: in [mission_brainstorm.md](mission_brainstorm.md) since 2026-10-11.
- The Arma mod research doc.

**cghath's dropped wave 3 extras**, for Captain's side to take or leave. They're on cghath's
local branch `local/wave3-cghath` and never pushed:
- CPR slows the 10-minute arrest window fourfold and holds oxygen up.
- Blood pressure; a slow heart pumps less and a racing heart bleeds more.
- IV lines pull out when carried, dragged or sprinting, and can be removed by hand.
- IO in the humerus and tibia, never into a broken bone.
- Wall-adjacent blast doubling, and flashbang facing.
- A breathing-sound hook.
- About 380 more medical test checks.

**Noted in the comparison against the design doc:**
- Falls can kill from 6 m; the doc says about 10 m.
- Hypothermia counts standing still.
- AI non-medics may use the needle, IVs and epinephrine.
- A heart-rate comment says 150/45, while the code uses 200/35.
- The epinephrine roll cancels a running concussion knockout.

## Open questions for Captain (all in one place)

1. A voided contract (8 civilian casualties): does it claw back the 30% advance? Today it does.
2. A hot zone with several contracts: is the 8-casualty void per contract or per deployment?
   Today it's per deployment.
3. Hot zone size: 8-16 km² (twice the area) or 16-32 km² (twice the width)?
4. Where can the contract board be reached: only at the FOB, or also from the main menu?
5. ~~Who fields the AH-1Z, MRAPs, Bradley and Abrams?~~ The US, and close allies that operate
   those exports (Captain, 2026-10-11).
6. The wave 6 decisions above: the support-menu limit and the faction set. (Reputation tiers,
   ripple, decay and allied troops are decided in [mission_brainstorm.md](mission_brainstorm.md).)
7. Should players start in their role kit? `CompoundLevel.player_role_kits` is off; 4A's
   roster kits AI squadmates out.
8. The M855 rule: does it count as level III beyond about 200 m?
9. Is the fragment serious-wound rate right? This is from wave 1's tuning.

## References

- Repo: `cghath/Contractor`, branch `dev`; CI on GitHub Actions runs every suite on push.
- Engine: Godot 4.7.2 with Zylann's Voxel Tools 1.7. On Windows, the custom editor is at
  `%USERPROFILE%\Downloads\GodotVoxel_1.7\godot.windows.editor.x86_64.exe`.
- Tests: `GODOT=... tools/run_tests.sh [suites]` (20 suites).
- Builds: `tools/make_build.sh <label> "<notes>"`, which writes `builds/<date>_<label>/` with
  `play.bat` and `BUILD.txt`.
- Design: `docs/contractor_design_doc.md`. Decisions and agreements:
  `docs/contractor_handoff.md`. Waves: `docs/build_plan.md`. Wave 4B: `docs/wave4b_handoff.md`.
