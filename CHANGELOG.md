# Changelog

All notable changes to Contractor are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Add new entries under
**Unreleased** in the same commit as the change. The README's "Versioning and changelog"
section explains how to cut a release.

Entry types: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## [Unreleased]

### Contractor: Fallen, phase A: the melee core fixed and the melee weapons (claude/survival, S2b)

Local: survival suite (see the run numbers in docs/survival.md's "Where the build is").

- **Fixed (melee):** a parry was judged against the moment the strike's timer fired, so a slow
  frame that landed a strike late turned a timely block into a plain block; it's judged against
  the landing the windup promised (`Melee._land(..., land_at)`), and a dodge begun before that
  landing counts too. The suite's melee checks poll frames up to the moment instead of racing a
  second timer, and count wounds rather than compare blood volume (R2607-R2611).
- **Added (melee weapons, calls 86-89):** weapon items with a `melee` stat
  (`MeleeWeapons`): one-handed in the sidearm slot (Combat Knife, Machete, Hatchet, Crowbar,
  Length of Pipe), two-handed in the primary (Baseball Bat, Felling Axe, Sledgehammer, Spear),
  each with a light and a heavy (windup, energy, stamina), a reach and a kind (blade, blunt,
  point); voxel models (`VoxelArt._melee`) with hand points. A player's swing lands on the head
  when his view is on it; a heavy there (`HEAD_ONE_HIT_J`) or a round drops a walker outright, a
  light there takes `HEAD_LIGHT_SHARE` of the pool (two or three kill); swings cost stamina and
  refuse when there's none.
- **Added (controls, `MeleeInput`):** with a melee weapon up, fire = light, fire held = heavy,
  aim = block (a block raised just before a blow lands parries), a movement key double-tapped =
  sidestep or dodge that way (the owner moves; the host's i-frames); with a gun up, **V** is a
  shove with the butt (`quick_melee`; V is also get_out, seated only); behind an unaware zombie
  with a blade (any blade; the starter knife on the rig counts), **Ctrl** is the **silent kill**
  (2 s, no noise; seen if it turns in time). One RPC, `Soldier._server_melee`.
- **Changed (survival):** the starter kit adds the Combat Knife.
- **Added (the stealth model, calls 29 and 33; phase A step 3):** `ZombieAI` has an awareness
  (0..1) fed by three senses and shown as a state: sight (by day, by night and between by the
  darkness, half for a crouched or prone man, the weather's sight cap and spotting factor, a line
  of sight; rising by how well it sees), sound (`hear(pos, loud)`: a shot fills it at once, a step
  a little; footsteps are heard by pace and stance: `Survival._footsteps`, a sprint 25 m, a walk 6,
  crouched 3, prone 1, less in rain), smell (a bleeding man downwind within 30 m, or 10 m any way
  in calm air: `Soldier.smell_strength`). States idle, suspicious (investigating), **alert** (it
  stops, faces him and groans; awareness still rising), chasing, searching; the silent kill needs
  an unaware one. The player's HUD (`Hud.StealthTells`, diegetic first): a thin ring under the
  crosshair that pulses when he makes a noise the dead could hear, sized by how far it carried,
  and a small eye above it while one of the dead has its eyes on him (`Soldier.server_watched`).
  A landed swing is a small noise (8 m).
- **Added (S3: the crowd, pressure, hordes, the specials; phase A step 4):** `ZoneDead`, the far
  tier of the dead on every survival zone (a record a head, the host walking them, one packet
  every 0.5 s, a MultiMesh stand-in a kind: `VoxelArt._crowd_zombie`); a crowd head within 70 m
  of a player becomes a body and a body past 110 m of everyone goes back into the crowd where it
  stood. **Zone pressure** (`Survival.pressure`, 0-100: shots and noise raise it by their
  loudness and reach, a half-life of 6 world hours, the pressure point drifting to the loudest
  noise); the crowd drifts toward it from 20; at **80 a horde** of 30-60 forms from the zone's own
  dead 150-250 m from the point and walks at it (once a 15 minutes), thinning once the pressure
  falls under 30; hordes never cross from another zone (call 22). Zones start with a crowd seeded
  round their sites. **The specials** (call 19) as kinds: the screamer (its first alert is a
  scream heard 120 m, pressure +25), the crawler (prone, half as easy to see, its attack a grab
  that trips him: `Melee.server_trip`), the bloater (slow, a big pool; bursts on death: a noise,
  pressure +10, the taint on anyone within 4 m), the hazmat one (a quarter of body damage, the
  head as any); rolled by the site's type (`Survival.SPECIALS`: the city most, none in the open).
- **Added (the cold open, permadeath, world options; phase A step 6, calls 7, 13, 41, 49, 51, 64):**
  `ColdOpen`: a new world wakes you at the farm with a note on the table from whoever was here
  (`handwritten_note`, six authors) and what they left, the nearest village marked on the map, the
  farm marked, day one's line in the journal, and a thing nearby rolled from the seed (a walker in
  the barn, the well gone bad, a wreck on the road with a part, or quiet), with day one's weather
  from the seed; the first night brings a little pressure to the farm. **Permadeath**: a dead
  survivor is gone; the player wakes at the safehouse as a new one (a new name from `Names`, the
  next generation, the journal and a message say so; the body and kit lie where they fell). **The
  New world screen** (`NewWorldScreen`): name, seed, the goal (Reach the evac, Sandbox, Clear the
  map), four world options Low/Normal/High (the dead, loot, needs and medicine, the living
  world) kept in the save (`Survival.option`, `option_mult`, `dead_speed_mult`: the dead's density
  and night speed read them now; loot, needs and the living world read them as they land), and the
  survivor as a blank slate (backgrounds and flaws come with the RPG layer).
- **Changed (ZombieAI):** sight is a forward cone (`SEE_DOT`, about 100 degrees each side): behind
  one of the dead you are unseen, which is what the silent kill needs (survival R2618/R2619 found
  it seeing all round).
- **Added (perf, phase A step 8):** the `fallen` suite (tests/fallen_test.gd, on perfcases' meter): a
  survival night at the farm with the live cap of the dead about the player (most chasing), a crowd
  of 200 in the far tier and a horde of 50 walking in; Proposed budgets beside the fight case's
  (avg 110 / p95 180 / hitches 140 / physics 6 ms, LOCAL_SLACK off CI). In run_tests.sh and CI.
- **Added (tests):** three verdicts in `tools/run_tests.sh` (the Captain: orange for a flaky
  test, red for a failed, green for a pass): a suite that fails is run once more; passing the
  rerun it's **FLAKY** (the run exits 0, the first try's logs kept as `<suite>.first-fail.log`),
  failing again it's **FAIL**; folders, `summary.txt` and `index.txt` carry the verdict, coloured
  on a terminal. `RERUN_FLAKY=0` turns the rerun off. docs/debugging.md.

### Everything merged for one test build (integrate/oct25, v0.7.0)

Every branch with work not yet on dev, merged on integrate/cg-oct24 (v0.6.1) at the Captain's
ask ("make sure all of the work we have done locally is on dev too"): cghath's operations lane
(ops/contracts D3 and ops/types D4/D5, their own entries below), the co-op soak harness, and
mission variety's board rules. Left off on purpose: claude/survival and claude/svd-model (the
Captain: "needs to stay here for now"); the 2026-10-14 handoff stubs marked untested WIP
(feat/squad-comms, ai/movement-quality, perf/frame-rate, fix/drag-direction) whose work was
done since on other branches (voice orders and barks, the movement feel pass, the perf passes).
Checked and already in: the helicopter door-seat and vehicle _exit_tree fix, the 2026-10-20
economy overhaul, the ragdoll stand-where-it-lay fix, the weapon-model iron-sight rework.

- **Added (tests, tools):** the co-op soak harness from claude/coop-join (tests/coop_soak.gd,
  coop_fake_human, coop_replay, soak_wedge_test; tools/coop_soak.sh, coop_relay.py,
  coop_soak_report.py, coop_watch.sh): bots that host or join a session and play a contract,
  including joining the Captain's own hosted game (agent-tools/bots_join_me.ps1).
- **Added (net):** the build check on join (`BuildInfo`, `Net._expect_hello`): a client says its
  commit on connecting; a host on a different known commit refuses it with the reason, and a
  peer that never answers gets a warning only (an older build). The main menu's hint and the
  pause menu show the build label.
- **Changed (contracts):** the safe offer stays one of the four plain types (raid, HVT capture,
  hostage rescue, intel grab); a hot zone's live contracts keep to sited types (convoy, crew
  rescue and recon stay off that board); `ScenarioGen.build` takes the module to play at.
- **Fixed (medical):** a casualty freed mid-treatment (its player left) no longer stops
  `_timed_care` with a script error (`_log_care`'s target untyped).
- **Merge notes:** followups.md kept both sides' additions (cg's D3-D5 calls, our F-08 section);
  contracts.json kept the newer sabotage brief; net.gd kept the 20-60 s timeouts with the hello
  check added in `_on_peer_connected`; menu.gd and pause_menu.gd kept the UiKit layouts.

### The rest of the reds: map, contracts, perfcases, casualty, roles (integrate/cg-oct24, v0.6.1)

Local R2581, R2583, R2584 (perfcases, townperf, city) and R2585 PASS.

- **Fixed (net):** a joined peer whose game was busy ~5 s (a client generating its zone on join,
  a host switching levels; slow PCs and CI) was dropped, and the client came back as a new peer
  (map's and lhd_home's CI reds). The connected timeouts are now 20-60 s, set on the host's link
  to each client too (`Net.ENET_TIMEOUT`, `_on_peer_connected`). Proposed.
- **Fixed (voxels, F-233):** a city's blocks stamped a fixed 4 ms a frame, so at 2-3 frames a
  second a city took minutes to appear. On slow frames the budget is 3% of the last frame, up to
  12 ms a block (`VoxelWorld.BUILD_FRAME_SHARE`, `BUILD_BUDGET_MAX_MS`); over ~12 fps unchanged.
- **Fixed (squad AI, F-192):** a follower whose slot swung round a building replanned north of
  it, then south, and ran loops. A new path that sets off the other way is taken only when it's
  under 75% of the old way's length (`KEEP_WAY_SHARE`), the old way kept at most 3 re-plans,
  only with its end within 4 m of the new spot and never while blocked.
- **Fixed (economy sim):** its campaigns started from whatever the last one (or a test's earlier
  sections) left in bounties, the war and zone control, so one seed ended $50k apart; each now
  starts empty and the caller's campaign is put back after.
- **Tests:** contracts' careless-play bar is -$25k (was -$50k: sloppy loses $36k in 14 days
  since the bounties and income streams; how hard careless play should bleed is the economy
  follow-up's) and its zone UI check takes a belligerent holder (the US gains ground); roles
  quiets every squadmate's brain for the held-back Moving! (a third man's lines held the air).

### The high command reds: base_zone, loop, forest, story, lhd_home (integrate/cg-oct24, v0.6.0)

Red on CI since high command C2 (b066b9ed, two standing squads) and the mission UI pass; local
R2578 and R2579 PASS.

- **Fixed:** the map's briefing screen started a contracts campaign and rolled a board on a host
  with none (the Experimental forest): asking `Contracts.contract` for the held contract does that
  lazily. It now asks only when the host has a contracts campaign (forest's "nothing went into the
  campaign").
- **Tests:** base_zone picks one of the player's own men (a standing detachment's "deploy with
  their high command squad"); loop counts its hires without the standing detachments, counts a
  captured leader's bounty in the bank check (as base_test does), drops again when the first drop
  only emptied the hands, and flies its heli contract in clear weather if it rolled a grounding
  storm; loop and story leave the standing detachments home (out in the zone they're "Leaving
  behind" at every extraction and crossing, by design: high_command_test covers them);
  lhd_home's client stops quietly when a first join's session ends and Main reloads the scene
  (slow CI), instead of running on out of the tree into script errors.
### The operation types: combined arms D4 and D5 (cg_brief queue item 3.3 (D4/D5), ops/types)

All five operation types are posted and play end to end: the phased invasion made full, the
armoured thrust, the beach landing, seizing a crossing and holding a town. Each has its own
phases, company tasks, order of battle, H-hour, pay and offer rules, and its own mechanic.
Attached armour and allied fires now work on every operation. Design: docs/combined_arms.md 6.1,
6.3-6.5; numbers Proposed (data/operations.json, data/fire_support.json "allied_units"); calls
D4-1 to D4-15 and D5-1 to D5-14 in docs/combined_arms.md section 10 and under "Calls made" in
docs/audits/followups.md. Closes F-288 and F-292; follow-ups F-294 to F-302.

#### Added
- **Who posts what.** US forces post the phased invasion, the armoured thrust (inland fronts only)
  and the beach landing (coast fronts only). Vessmark posts its smaller ones, seizing a crossing
  and holding a town, so D7's stand-in Vessmark contract is gone. Every type needs the employer
  at trusted (30). An operation is rated by the ground it fights over and the waves it sends,
  not by every garrison in the 8 km zone.
- **Attached armour** (the invasion's Abrams section, the thrust's Bradley section). It comes out
  at the start line at H-hour with an allied driver and gunner (and loader), and the commander's
  hatch is left free for a player. By default it overwatches the company's task from 300 m back.
  Support > Operation > Attached armour orders it to move, hold or follow, and a player aboard can
  take its gun and hand it back. A lost vehicle is the employer's loss.
- **Allied fires.** The employer's mortars (fired from the mortar section's real tubes), its
  battery and naval gunfire fire the operation's rounds. They fire preparation fires on each
  phase's enemy sites, smoke when the allied commander asks for it for a breach, and three rounds
  wherever the company calls them (Support > Operation > Allied fires), never danger close.
- **The phased invasion, full.** Its full order of battle, with a mortar section, an ammunition
  and a fuel truck that rearm and refuel the armour at the logistics point behind the front, and
  the employer's Dustoff flying the company's first two medevac calls. In phase 4 there's a
  bonus for taking the HQ's commander alive.
- **The armoured thrust.** The column (the Abrams and mechanised platoons, plus the attached
  Bradleys carrying the company) drives down the MSR and halts short of each blocking position
  until the company has cleared it. It moves on once everyone is aboard. Support > Operation >
  Column can bypass a position off-road, if the ground allows, but that leaves its enemy behind
  the front. The whole thrust has 45 minutes, and it fails if the column loses half its vehicles.
- **The beach landing.** It starts before dawn with the company in its AAVs in the LHD's well
  deck. Wave 1 (the company's two AAVs and four allied ones) swims in on its lanes, and wave 2
  follows four minutes later. Artillery and naval gunfire hit the known beach defences, then
  smoke goes on the exits. H-hour is when wave 1 hits the sand. The phases are the left beach
  exit, the harbour, then holding the beachhead against a counterattack.
- **Seizing a crossing.** The bridge has three charges under its middle span, wired to a firing
  point on the far bank where two engineers wait. Once they see us within a kilometre, they blow
  it 90 seconds later; a vehicle on the span sets it off at once. To stop it, kill them, cut the
  wire at a marked point (Support > Operation > Cut the firing wire) or take the firing point. An
  intact bridge pays +40% of phase 2. If it's blown, the armour crosses at a ford.
- **Holding a town.** The company starts in the town it has just taken (a city), beside an
  allied platoon, two Bradleys and mortars. It gets ten minutes to dig in, site its guns and
  place six pieces of field defences (Support > Operation > Field defences: sandbag wall, HESCO,
  concertina wire). Then two or three waves come in, each from the approach the enemy picks
  round what it has seen of the defence, so a hidden piece pays off. The second wave brings
  technicals and comes after a mortar barrage. Hold the centre to win.
- **On screen and after.** The operation strip gets a line for the type (the column, the AAVs,
  the bridge's charges, the defence and its waves), and the debrief lists what happened in it.
- **The optypes suite** (tools/run_tests.sh and CI): each type offered, taken, played through
  its phases and its mechanic, paid, saved and loaded, debriefed and fed to the war, with a client
  joining late and following the host into each zone.

#### Changed
- FireSupport can fire an operation's own guns (`server_allied_fire`), and FireMission reads
  their units from data/fire_support.json "allied_units". The company's fire support is
  unchanged.
- DefencePlacer has a field mode for the town's defences. The base's defences are unchanged.
- OperationGen starts a town-holding operation's insertion in its town.

#### Fixed
- A client already in the session is no longer dropped when the host switches to an 8 km
  operation zone. Every end now waits up to three minutes while the zone is made, as a late
  joiner already did (BaseHub, F-302).

### Operation contracts: combined arms D3 (cg_brief queue item 3.2 (D3), ops/contracts)

The big government jobs can be taken and fought. A belligerent employer at war posts an operation
contract on its front: the company joins its battlegroup in an 8 km operation zone, fights it phase
by phase beside the allied commander, and is paid as each phase is done. The result moves the war.
Design: docs/combined_arms.md 6.1, 6.3, 6.5, 6.6 and 3.5; numbers Proposed (data/operations.json);
calls D3-1 to D3-21 in docs/combined_arms.md section 10 and under "Calls made" in
docs/audits/followups.md. Closes F-286; follow-ups F-288 to F-293.

#### Added
- **Operation contracts.** US forces post a phased invasion on their front (Contracts'
  operation offers; their factions.json `operation_types`). It covers the front's zone and up to two
  neighbouring zones the target holds, in an 8 km zone made for it. It needs the employer at
  trusted (30) to sign. Vessmark keeps D7's stand-in until its types (D5) are built. The armoured
  thrust, beach landing, seize crossing and hold town types are in the data but not posted yet.
- **Phases.** Four phase lines (PL COPPER, the outposts; BRASS, the crossing; IRON, the town;
  STEEL, the HQ and the depth), each with a time limit, a pay share, the allied objectives and the
  company's own task: seize the MSR checkpoint, the bridge (and keep it standing for a bonus), the
  town centre, the HQ. A phase is done when its task and its required allied objectives are. It
  stalls at 1.5 x its limit, and the operation stops there.
- **The allied and enemy commanders run it.** The friendly side's commander gets an operation plan
  made from the phases. It moves on as objectives fall, sends its reserve, and falls back to the
  last line it held when it withdraws. The enemy's commander defends the sites band by band.
- **The order of battle comes out by the front.** Allied rifle squads, Bradley sections and an
  Abrams reserve start at H-hour. The enemy's roamers, QRFs, AT teams, gun teams, mortar team and
  light armour come out when a player is 0.6-2.6 km from them and nobody can see the spot, two men
  a frame, within the live caps. Waves come in on the enemy's side of the front, teams slip in
  behind it, and IEDs lie along the MSR.
- **The front.** The zone is 32 x 32 cells of 256 m, each held by a side. A cell flips where one
  side has twice the other's presence for a minute and no garrison of the other stands. Cells
  flip at once as objectives fall. A phase done takes everything short of its line, and a
  withdrawal gives back everything past the last line held. The front is saved, replicated (a
  late joiner gets it whole) and drawn as a line on everyone's map.
- **The operation strip on the HUD** (top right, over the objectives): the operation, each
  phase's state, the clock against the limit, the company's task and how far the front has come.
- **Pay by phase.** 20% on signing. Each phase pays its share of the rest into the bank when it's
  done (one ledger line each), with its bonuses (fast, low allied losses, allied asks answered, no
  civilians hurt, the bridge kept) and penalties (late, friendly fire). The debrief shows it phase
  by phase, outcome completed, partial or failed, and pays nothing twice. Company vehicles lost
  are half reimbursed.
- **The war hears it.** The phases done go to the living war (WorldSites): carried, the covered
  zones change hands; half or more moves the front there. The debrief says which zones moved.
- **For D4 and D5.** `Operations.register_type(type, data, hooks)` and its hooks (phases, start,
  tick, phase_begun, phase_done, task, pay, h_hour), the objective kinds seize_site, hold_line and
  keep_intact, and `Operations.make_offer` with a type.
- **The `operations` suite** (two processes: host and late joiner), in run_tests.sh and CI.

#### Changed
- Contracts: an operation is signed with its 20% advance (`Operations.deal`). Its debrief is
  written phase by phase (`Operations.debrief_into`) and the completion already paid is taken off.
  The war hears the phases done. A held operation's covered zones are in the war snapshot.
- The objectives panel makes room for whatever sits above it in the HUD's top-right corner.
- The economy sim plays an operation phase by phase through the real pay, and skips offers the
  company can't sign.

#### Fixed
- A client joining an 8 km operation zone was dropped while it made the zone (10-60 s, past the
  30 s authentication and ENet timeouts), then tried again from the start. Now both ends wait up to
  3 minutes while it loads, then go back to the normal timeouts (LevelSwitch, `LOAD_TIMEOUT`).

### Operation zones of about 8 km: combined arms D1 + D2 (cg_brief queue item 3.1, ops/zones)

The big government operations get their ground: 8,192 m zones made fresh from the contract zones
they cover, and the streaming that lets one run. Design: docs/combined_arms.md 6.2; every number
Proposed (data/operation_zones.json, named consts); calls D1-1 to D1-12 and D2-1 to D2-13 in
docs/combined_arms.md section 10, the rest in docs/audits/followups.md "Calls made". Nothing offers
or hosts an operation yet: that's D3 (cg_brief 3.2), which builds on `ZoneDef.generate_operation`.
This finishes the work left on claude/ca-d1-operation-zones (D1 done, D2 untested then), merged
onto armour/drive and re-applied to the world expansion and the perf pass that came after it.

#### Added
- **Operation zones.** `ZoneDef.generate_operation(seed, op_type, covers)` makes an 8,192 m zone
  for the big government operations from the contract zones it covers. It takes their region,
  terrain (river valley, desert wadi, farmland or marsh inland; the coast presets for a landing),
  assets and landmarks, and lays them out with today's water, roads, villages and landmarks.
- **Bands along an axis of advance.** The zone runs from the friendly edge, or the sea, into the
  enemy's depth. First comes the start: an allied FOB inland, or the beach on the coast. Then
  outposts, checkpoints and villages. Then a river crossing, then the town, then the HQ with its
  comms site, QRF bases and the depth target (an airfield, an oil site or a fuel depot). The
  enemy's rear comes last.
- **The main supply route.** The MSR runs the length of the zone: start, its checkpoint, the
  river, the town, the HQ, the depth target. Two laterals cross it, and every other site has a
  track to the nearest road. The roads are curved and graded like any zone's.
- **A river with real crossings.** The river crosses the axis in band 2. The MSR crosses it on a
  concrete road bridge. A second route has a steel truss bridge, and one or two tracks ford it.
  Footbridges sit between them for the infantry. A checkpoint holds the far end of the bridge,
  with an outpost overlooking it.
- **Landmarks from the covered zones**, each in its own band. A beach landing's harbour stands on
  the coast. The mosque and the office are in the town, and the airfield and oil field are in the
  depth.
- **Holding a town means a city.** An operation to hold a town puts one of cghath's cities in the
  town band, where the town would be. The MSR comes in at its ring street on the bridge's side and
  leaves on the far side.
- **An 8 km zone streams its ground** (BigZoneStreaming, on every peer):
  - the ground's collision is built round every player (1 km), vehicle (300 m) and soldier (150 m;
    450 m on the host for a squad in a fight), nearest first, a little every frame, and freed
    once everyone has gone; the cover (trees, rocks, props) the same by its 128 m cells;
  - a chunk with something lying on it (a body, a dropped item, a wreck) is kept, so nothing
    falls through the world;
  - a late joiner, a respawn or a spawned vehicle gets the ground round it at once, anywhere on
    the map;
  - a door gunner going fast or high keeps his ground but not the far cover, as the perf pass
    already does for navigation.
- **The ground is drawn in rings.** An 8 km zone's terrain is 256 far tiles from 2 km out, and
  each chunk's own detail levels built on a worker round the camera and freed behind it. The
  scatter frees its drawn cells behind the camera too. Driving or flying across the zone holds the
  memory steady instead of filling it.
- **Far drawing.** In an 8 km zone soldiers are drawn to 1.5 km and vehicles to 1.2 km, with a box
  of their size and colour out to 3 km.
- **Live caps.** Past the Virtualizer's force-spawn distance, a group waits as a profile while 80
  soldiers (or, for a ride, 16 vehicles) are live. Nobody near a player is ever held back.
- **The `invasion` suite** (also on CI): the 6.2.3 case on an 8 km operation zone, with two armour
  columns on the move, 60 live AI fighting, 200 virtual and one player. Then a drive along the MSR
  and a UH-60 contour flight across the zone, measuring how fast the ground catches up. Then the
  same load in a 4 km hot zone on the same terrain, built up front, to hold it against. It measures frame and physics time, hitches a
  minute, the streaming's worst frame, the catch-up and the memory, against Proposed budgets.
  It replaces the WIP's tests/invasion_perf.gd timing script.
- world_test: the D1 checks, plus the city for holding a town, a crater cut before its chunk is
  built (a save's cuts) still there when the chunk comes, a chunk kept while something lies on
  it, and the ground's rings.

#### Changed
- cghath's world files (each change only for zones of 4,224 m or more, apart from two that come
  out the same everywhere): ZoneTerrain (collision on demand; far tiles and rings; a chunk's
  collision read from the height grid by rows, and `_wanted_near` only looking at the chunks near
  the camera, both giving the same chunks as before), ZoneScatter (caps scaled by area, cover
  streamed by cell, drawn cells freed, the layout let go from memory as its zone goes; a cell's
  cover body now gets its shapes before it enters the tree, which builds the same collision
  faster everywhere), ZoneWater, ZoneBridges and ZoneModules (one hint each, F-195 to F-197).
  Hot and contract zones build and draw everything up front as before.
- perfcases' meter takes a case's length and a per-tick hook from a subclass (the invasion suite
  extends it); perfcases itself runs as before.

#### Fixed
- The D2 work-in-progress had pasted ZoneScatter's new `_cap()` into the middle of `_set_caps`, so
  the woods' and copses' shares were never set on that branch (it never ran a test). Fixed in the
  merge; armour/drive never had the bug.

### Driving physics and terrain for armour (cg_brief queue item 2.7 (A6), armour/drive)

Combined arms phase A6: vehicles drive by their engine's power and the ground's grip, can roll over,
ford rivers up to their depth, swim, flood, bog down and break bridges too light for them. Design:
docs/combined_arms.md 2.8; every number Proposed (data/vehicle_drive.json, ZoneBridges.TYPES);
calls in docs/audits/followups.md "Calls made".

#### Added
- **The ground under a vehicle**: asphalt and dirt roads, a town's streets, packed earth on the
  sites, mud in a river or lake bed (gravel on a ford's track), marsh mud, snow, rock on steep
  ground, sand in dry riverbeds and on beaches, grass elsewhere, asphalt on a bridge's deck. Each
  has its own grip for tyres and for tracks and its own rolling resistance; tyres are capped at
  40 km/h on sand and 25 km/h in mud, and narrow tyres sink deeper than wide tracks.
- **Engine power**: every vehicle has its real engine (the Abrams 1,120 kW, the Bradley 450, the
  AAV 390, the M-ATV 276, the MaxxPro 280, the technical 110). It pulls by its power over its
  speed, so a light pickup leaps away, an MRAP is quicker than an IFV, and a hill slows a heavy
  vehicle to what its power can climb (a 20 degree hill: an M-ATV about 16 km/h, an Abrams 13,
  a Bradley 11). Whether it climbs at all comes from power and grip: a MaxxPro tops a 15 degree
  dirt hill and spins to a stop on the same hill in mud, where an Abrams' tracks carry on.
- **Real centres of mass** (the M-ATV's 1.25 m up, the MaxxPro's 1.35, the tanks' low) and
  **rollovers**: past its tip angle (half its track over that height: the MRAPs about 40 degrees,
  the Abrams 57) a vehicle goes over. The crew is hurt (a belted seat less, an open hatch more), it
  can't drive, and the HUD says ROLLED OVER. ROLLOVER RISK shows from 70% of the tip angle, with
  the numbers. Righting it: hook it up at its service point to a vehicle of at least half its mass
  (60 s), which pulls it back onto its wheels, still on the tow; or abandon it.
- **Tracks** turn on the spot at a standstill, half as fast by 30 km/h, slower in mud; a hard pivot
  at speed on rock or rubble, or on a side slope, can throw a track.
- **Bogging**: an MRAP that spins to a stop in mud on a slope is stuck (BOGGED: NEEDS A TOW)
  until a tow pulls it out.
- **Fording**: each vehicle has its depth (the M-ATV 1.37 m, the Abrams 1.2, the Bradley 1.0, the
  MaxxPro 0.9, the technical 0.6). The HUD's FORD line shows the water against it. Deeper, the
  engine stalls at once, is damaged after 5 s and destroyed after 20 s; water over the roof
  floods the crew compartment and everyone gets out (and nobody can get in). Mud banks hold a
  vehicle in the river: columns cross at the fords and the bridges.
- **Swimming**: the AAV swims at 13 km/h on its two waterjets (each one's damage costs push, one out
  pulls it round, both out and it only drifts); the river's current carries a swimming hull
  downstream and pushes a grounded one. A hull holed under its waterline takes on water faster
  than its pumps clear it (FLOODING with the share), floods and sinks.
- **Bridge load classes**: concrete bridges MLC 80, steel truss 40, footbridges 2, falling with a
  span's damage. A vehicle's class is its mass with its packages (the Abrams 62, 66 with TUSK II).
  Over a span's class the span weakens and gives way (about 8 s at 1.5 times its class). The HUD
  warns approaching one: BRIDGE MLC 40: TOO HEAVY.
- **The AI driver** keeps its corners under 60% of what would tip it, stops short of side slopes
  over 60% of its tip angle, water deeper than it fords, grades it can't climb and spans too light
  for it (then backs off and goes round), and its road routes leave out bridges too light for it.
  A9's API: TerrainRoute.can_cross, ford_ok, slope_ok, path_problem, roads_for.
- The tow bar is drawn between the hitches, and a tow is saved with the zone.
- New suite `armourdrive` (in tools/run_tests.sh and CI).

#### Changed
- Ground vehicles no longer carry the engine's default linear damping, which held every one of
  them near 50 km/h whatever its engine; air drag takes its place, so they reach their top speeds.
- The old 35 degree grade hold is gone: power and traction decide what a vehicle climbs (part
  throttle still holds a grade as far as the engine's power goes).
- Rolling resistance comes from the ground on top of the tyres' grip.
- River water drags a hull through the water as it moves with the current.
- Rolled-over, flooded, bogged and stalled states, water aboard, a drowning engine's seconds and
  the tow replicate to every peer and late joiner and go in the zone save; so does a bridge span's
  health (now sent to the clients as it falls, not only when it drops).

### Logistics, repair and armour packages (cg_brief queue item 2.6 (A8), armour/logistics)

Combined arms phase A8: tank rounds are things you carry, stow and run out of; a broken tank is
fixed module by module in the field or at the motor pool; a disabled one is towed home; and armour
packages are bought, fitted and paid for in speed and fuel. Design: docs/combined_arms.md 2.9,
2.2.2 and 2.4.5 ("Built in A8" there); every number Proposed (data/vehicle_logistics.json,
data/prices.json "ammo" and "packages", data/ground_supports.json "module_prices"); calls in
docs/audits/followups.md "Calls made".

#### Added
- **Rounds as items**: 120 mm M829A3, M830A1 and M1147 rounds (21-24 kg, carried in both hands),
  25 mm cans of 50 (M791, M919, M792), TOW-2A missiles, 40 mm Mk19 cans, vehicle smoke salvos, and
  the enemy's 125 mm and 30 mm rounds as salvage. The racks hold them: firing a sabot takes one
  out, Check vehicle lists each rack by round. All of them in the shop, priced per round.
- **Rearming** at a vehicle's cargo point (Left Ctrl > Rearm), the vehicle stopped: from your own
  kit, from its hold (a crewman can do that from his seat), from another vehicle's hold within 8 m
  (any truck carrying rounds, twice as fast) or from an **ammunition pallet** within 8 m. 10 s a
  120 mm round, 15 s a can, 30 s a TOW, 10 s a smoke salvo; each goes into the right rack, and the
  job pauses while you're under fire or the vehicle is hit. Rounds come out the same way (Take
  out rounds). Pallets per calibre (120 mm, 25 mm, TOW, smoke, fuel drums) are too big to carry:
  a truck loads one from beside its cargo point, and a helicopter resupply now brings each of the
  company's tanks and IFVs the ammunition it's shortest of (8 x 120 mm, 300 x 25 mm or 2 TOW).
- **Field repairs by module** at the service point: track links for a thrown track (3 minutes with
  two men, 6 alone), a spare wheel, a repair kit for a damaged engine, transmission, turret drive
  or mounted gun, a patch for a holed fuel tank (the leak stops), a spare periscope or radio, a
  spare ERA tile or slat panel (from the hold) for one that fired. Repairs bring a part back to
  60% and clear the kill states with it; the work done stays on the part if you walk off, and the
  job pauses under fire. A destroyed engine, breech, barrel, sight, fire control, ammo rack or
  hull is the motor pool's.
- **The motor pool** quotes and fixes each part (a destroyed module costs its share of the
  vehicle's value; fired tiles their spares), rearms vehicles going out and coming home to the
  **load-out** you pick (standard, anti-armour, urban) and charges the rounds and smoke it puts in,
  and refills the extinguisher bottles.
- **Armour packages** at the motor pool page: fit TUSK I/II, Trophy, BUSK III, the slat kits, the
  spall liner, CROWS, the M-ATV and **MaxxPro appliqué ($40,000)**, the mine roller or the thermal
  kit for their price and days in the workshop (some need standing with the US, Trophy needs TUSK
  I, TUSK II credits a TUSK I already fitted); take one off for half back. Each keeps its STANAG
  4569 rating (shown on the page), and its weight costs top speed, acceleration and fuel.
- **Towing** (recovery): a vehicle that can't drive is hooked up to one at least half its mass at
  its service point (60 s, both stopped) and towed on a bar at up to 15 km/h; towed home inside
  the extraction's reach, it goes back to the motor pool.
- **Fuel drums**: refuel at 60 L a minute from a drum pallet on the ground or in a truck's hold.
- An API for AI crews and support (A9): what a vehicle needs, where it can rearm, what can be
  repaired, a recovery call.
- New suite `armourlog` (in tools/run_tests.sh and CI).

#### Changed
- On the M-ATV, MaxxPro, AAV, Bradley and Abrams the service point lists repairs by part ("Track
  Links: left track") instead of by zone; technicals keep the zone repairs.
- Fitted packages and fired ERA tiles now reach every player and late joiner and are saved with
  the vehicle (they were the host's alone), so the HUD's doll and the x-ray show them everywhere.
- The motor pool's quote for a vehicle with modules is per part, and its service now really makes
  every part whole (it left the modules' damage in the record).

#### Fixed
- The base suite's "the pay lands in the one bank" counts a captured leader's bounty: it failed
  whenever the board's draw gave the loop a manhunt or capture (the bounty is paid beside the
  debrief's pay since the war's bounties came in).

### Fire, destruction and sound (cg_brief queue item 2.5 (A7), armour/fx)

Combined arms phase A7: armour burns, cooks off and blows apart the way it should, the guns sound
like what they are, and the crew hears itself on the intercom. Design: docs/combined_arms.md 2.10
and 2.7.1 ("Built in A7" there); every number Proposed (data/vehicle_fx.json); calls in
docs/audits/followups.md "Calls made".

#### Added
- **Fires in stages**: a vehicle set alight smokes grey for a few seconds, then burns with flames,
  black smoke and a light; once it's a wreck it keeps burning for 2-5 minutes while the flames die
  down, its smoke column stands for 5-10 minutes (a tall billboard seen from past 600 m), then it
  smoulders for the rest of the deployment. Saved with the zone, and a player who joins late sees
  a burning wreck burning. A burning hull is hot in thermal and cools off once it's out.
- **Ammunition**: the Abrams' bustle vents through its blow-out panels as an 8 m column of fire for
  4 s and the tank fights on; a rack cooking off (the Bradley's 25 mm, the AAV's) pops a round
  every 0.5-3 s for 20-60 s, each pop a small blast on anyone close; a rack going up is a
  **fireball** sized by the rounds aboard, a blast on everyone near (up to 12 kg TNT) and a
  shake. With 10 or more main-gun rounds aboard the **turret is thrown** into the air and lands
  where its physics takes it (its crash heard), otherwise the hull ruptures; 12-24 pieces of
  **debris** fly off and come to rest; the hulk is charred black. The turret and the debris land
  in the same places on every machine and stay there in the save.
- **Bail-out**: AI crews get out when a rack cooks off or after a few seconds of flames
  ("Bail out!"); a catastrophic kill gives nobody the time.
- **Smoke dischargers** (the Abrams' M250, the Bradley's M257): "Pop smoke" on the crew wheel
  throws a salvo of grenades across the turret's front that makes a **multispectral screen**: it
  blocks sight, thermal and the laser until it clears. Two salvos loaded, a reload's worth stowed
  (10 s a salvo, stopped); a damaged launcher loses half its grenades. The HUD shows SMOKE 6 | 6.
- **Gun sounds**: the 120 mm's report (heard for kilometres) with a pressure thump and a shake
  close by, and the dust its overpressure kicks up; it rings the ears of anyone standing in front
  of the muzzle. The 25 mm's thud, the TOW's launch whoosh and the wire spooling out. Muzzle
  flashes, the gun's recoil and the hull rocking on a 120 mm shot. The **TOW launcher** visibly
  raises and lowers.
- **Impacts by round**: a ricochet sprays sparks with a ping, a stopped round sparks with a clang
  (steel), a thud (composite) or a clank (aluminium), a penetration flashes white with a muffled
  boom, a stopped HEAT round flashes orange with a black puff, HE bursts by its filling. Tracers by
  round: sabot white-hot, HEAT orange, HE red.
- **Inside the vehicle**: crew voices come over the **intercom** (band-limited, never muffled),
  buttoned up or turned out; your own engine and tracks are a louder, duller drone from inside
  rather than muffled with the outside. Tracks clatter louder with speed.
- New suite `vehiclefx` (in tools/run_tests.sh and CI).

#### Changed
- The fire's old orange sphere and light are gone (the new effects replace them).
- A burning hull blackens a smaller spot every 4 s instead of every second, and the hull's damage
  carving runs about 2.5x faster: eight burning vehicles used to hold the host to a few frames a
  second.
- A rack that goes up in a vehicle already on fire from the same hit still goes up at once.
- Wrecks in older saves smoulder.

### Vehicle HUDs and the x-ray (cg_brief queue item 2.4 (A5), armour/hud)

Combined arms phase A5, the first build cut: the Abrams and the Bradley (and the AAV, M-ATV and
MaxxPro) get their own HUDs, the x-ray shows what each hit did, and a buttoned-up crew sees and
hears the world from inside. Design: docs/combined_arms.md 2.6, 2.11 and 2.12 ("Built in A5"
there); every number Proposed; calls in docs/audits/followups.md "Calls made".

#### Added
- **The vehicle HUD** (any seat of a vehicle with modules; soft vehicles, helicopters and static
  guns keep the text line): a panel in the old line's place with a top-down **doll** of the
  vehicle (its modules white, yellow when damaged, red when destroyed; tracks or wheels; reactive
  armour tiles, grey once fired; a coloured pip with a letter for each crewman at his seat), the
  vehicle and seat with a short damage word (none, damaged, mobility, firepower, knocked out,
  burning), the **alerts** when they're true (ON FIRE, TRACK THROWN, ROLLOVER RISK, FORD depth,
  MISSILE LAUNCH, SHORT-CREWED, NO RADIO), the guns' lines, a **round selector** (every round
  type, the loaded one in brackets, the next named, the reload bar), the crew line (names, jobs,
  wounded or down, "you"), the drive line (speed, gear, fuel, engine and transmission) and your
  own keys. On a small window it drops the keys first, then the crew names, the drive line and the
  selector. The compass strip shows the hull's heading, the turret's direction and a red tick for
  where the last hit came from; in third person a ring shows where the gun really points.
- **Blue Force Tracker chevrons**: a blue chevron over every friendly vehicle whose radio works,
  in every view and through the sights. A vehicle whose radio is knocked out drops off it.
- **The sights** show the crew pips and the damage word, and bracket the loaded round.
- **Vision blocks and periscopes**: buttoned up in first person (the Abrams' driver, commander and
  loader, the Bradley's driver and commander) you see only through your blocks: thin slits of glass
  at 1x, the one you look towards; the sight (aim) and the third-person view are as before. The
  driver's three periscopes have a **night channel** (the sight channel key): green intensifier,
  the rest of the HUD dimmed; a damaged periscope loses it, a destroyed one means turning out to
  drive. The loader turned in sees the bustle doors and a large round selector.
- **Muffled hearing**: in a closed seat outside sounds are 12 dB quieter and dull; turned out or in
  an open seat, clear.
- **The x-ray** (5, rebindable; the pad wheel's "Last hit (x-ray)"; the pause menu's "Last hits"):
  after a hit on armour a small card says what happened ("PEN: transmission destroyed, engine
  damaged, loader wounded" or "RICOCHET: Turret side, 81 degrees"); the key opens the full view:
  the vehicle drawn from its data, turnable, its plates shaded by thickness, its modules and crew
  coloured by state, the round's line through what it hit, the angle, the spall, and the numbers
  ("Hull rear, 30 mm KE at 0 degrees: 30 mm effective. M829A3 at 1000 m: 780 mm. PENETRATION.").
  It reads what the host worked out for that hit, never a second guess. The last 10 hits are
  kept. A setting (HUD tab, "Hit analysis") picks the cards: off, my shots, my shots and hits on me
  (the default), every hit. `--xray-log` writes every report to the session log.
- **Protection analysis** at the vehicle range and the base: with no hit to show, the x-ray key
  opens it on the vehicle you're in or next to: pick a round and a range, click the model, and
  see what happens there and how often it ricochets.
- New suite `vehiclehud` (in tools/run_tests.sh and CI); ui_test fits the panel, the card and the
  full view at its 10 window sizes.

#### Fixed
- **Door gunners and mounted MGs fire again** near friendly vehicles. B5's armour IFF held every
  vehicle gunner off any enemy within 50 m of any friendly tracked vehicle, so a Black Hawk's door
  gunner or an M-ATV's M2 at the range (or in any convoy) never fired (vehicles suite: "engages the
  enemy out of his door (0 rounds)", "fires at an enemy in view (0 rounds)", red since B5). A
  machine gun now holds fire only when a tracked friendly vehicle is on its line of fire (within
  6 m of it, out to 150 m past the target, less when firing downhill). Its own vehicle is also
  recognised by the tracker's own key.

#### Changed
- HitEvents carry the round's direction, angle, range, shooter, path and spall for the x-ray
  (a few hundred bytes each); a vehicle's dead radio shows on every machine, not only the host.
- perfcases' city rechecked alone on a quiet machine: 51 hitches a minute against the local
  budget of 96 (R0633; the 322 after the armour merge was a busy PC). The hitches left are the AI's
  ticks (F-261), so the budgets stay.

### Gunnery: sights, thermal, the laser and fire control, the stabiliser, hatches (cg_brief queue item 2.3 (A4), armour/gunnery)

Combined arms phase A4: the Abrams and the Bradley aim through real sights. Design:
docs/combined_arms.md 2.6 and 2.7.4 ("Built in A4" there says what's in); the sights, fire
control, stabilisers and hatches in data/vehicle_weapons.json; every number Proposed; calls in
docs/audits/followups.md "Calls made". The full vehicle HUDs and the x-ray are next (A5).

#### Added
- **Sights, full screen**: the aim key in the gunner's or commander's seat looks through the
  seat's sight, at its glass on the turret, its power relative to your own view (zoom in and out
  step it; the mouse slows to match). The Abrams' gunner has the GPS (day 3x and 10x, thermal 3x
  to 25x, the laser to 8 km) and the GAS (8x, with a stadia mark per range for the round in the
  breech); the commander the CITV (thermal 3x, 6x, 13x, its own laser). The Bradley: the IBAS
  (day and thermal 4x and 12x, the laser to 4 km), its aux sight (6x, stadia) and the CIV. A
  minimal overlay gives the reticle, the channel and power, the range (first or last return),
  the stabiliser and laser state, the round loaded and next, the rounds left, the fuze, the lead
  and how long you've tracked, and the turret's and hull's headings.
- **Thermal** (the sight channel key: day, white-hot, black-hot): living men glow, a dead one
  less, a running tank warm, a cold one dim; ordinary smoke is see-through, a multispectral
  screen isn't; walls hide what's behind them. Local to your machine.
- **The laser and the fire control computer**: lase (E) and the computer lays the gun for the
  range, the round's ballistic table (from ShellFlight's own flight), the lead (how fast your
  sight was turning over the last second times the time of flight) and the sight's offset from
  the bore: the reticle stays on the target, the gun moves. It holds until the next lase, and
  re-lays for a new round at the same range. Smoke on the line gives a first return at the smoke
  (MULTIPLE RETURNS); hold lase to switch first and last. With no lase, battlesight: 1,200 m for
  sabot, 900 for HEAT and HE. Rounds from a moving tank carry its speed.
- **The M1147 AMP's fuzes** (the underbarrel key in a gun seat cycles PD, delay and airburst;
  the M830A1's PD and air): airburst goes off at the lased range.
- **The stabiliser**: the gun holds its line in the world while the hull turns and pitches, with
  a little more scatter the faster and rougher the drive; past 50 km/h (the Bradley 40) it can't
  keep up and the gun turns with the hull. Off, firing on the move scatters badly.
- **The commander's independent viewer and hand-off**: he looks all round through it apart from
  the gun; designate (Q) slews the turret onto his line at full speed for the gunner ("Gunner,
  sabot, tank!"), with the range he lased. With no gunner he lays the gun himself, holding
  designate, half as slowly again.
- **Hatches** (X): the driver, commander and loader turn out (head and shoulders out of the
  hatch, 1.5 s) or button up. Turned out, rounds and blasts reach them as anyone in the open,
  and they see all round; buttoned up they see only through their vision blocks, 2.5x slower
  for the AI to spot. The loader's M240 and the commander's M2 fire only turned out (the M2 from
  inside with CROWS fitted); the Bradley's TOW reloader works out of the roof hatch, exposed.
  AI crewmen ride turned out once it's been quiet a minute and button up at the first contact.
- **Module fallbacks** (A2's modules): the gunner's primary sight damaged leaves day only and no
  laser; destroyed, the gunner falls back to the aux sight (no solution, no stabiliser: hold over
  with the stadia). The fire control damaged triples the solution's error; destroyed, no
  solution and no stabiliser. A damaged traverse or elevation drive turns the stabiliser off.
  The commander's viewer damaged loses thermal; destroyed, no hand-off.
- New suite `gunnery` (in CI): the laser, fire control on real rounds at 1-2 km (static,
  crossing, from a moving tank), 200 seeded runs (90% hits with the lead, under 40% without),
  every fallback, the stabiliser, the hand-off, hatches, the AMP's airburst, thermal and its
  budget, the overlay at 10 resolutions, save and load, late join.

#### Changed
- The TOW's wire follows the gunner's sight line (it was the barrel's).
- The gunner's first-person view follows his sight's line.
- Spotting from a vehicle's hatch seats (driver, commander, loader) depends on the hatch.
- Keys: lase (E), designate (Q), hatch (X) and sight channel (C) work seated, sharing their keys
  with lean right, lean left, crouch and rest weapon on foot; rebindable, and on the pad's wheel.

### Main guns: the Abrams' 120 mm and its loader, the Bradley's dual feed and TOW (cg_brief queue item 2.2 (A3), armour/guns)

Combined arms phase A3: the tanks fight with their real guns. Design: docs/combined_arms.md 2.5
and 2.7 ("Built in A3" there says what's in); the mounts, turrets and racks in
data/vehicle_weapons.json; every number Proposed; calls in docs/audits/followups.md "Calls made".
Sights, thermal, the laser and fire control are the next phase (A4): A3 aims along the barrel.

#### Added
- **Turrets on the Abrams and the Bradley**: the turret and gun split from the hull and turn
  and elevate at the vehicle's drive rates (Abrams 40 and 25 degrees a second, -9 to +20;
  Bradley 50 and 30, -9 to +60). A2's drive modules now act on them: damaged halves a drive,
  destroyed is the hand crank (6 and 3 degrees a second), and with the engine dead the turret
  runs on its batteries for 10 minutes, then by hand. The commander's and loader's seats turn
  with it.
- **The M256 120 mm and its loader**: M829A3 APFSDS, M830A1 HEAT-MP and M1147 AMP, 34 in the
  bustle (16 / 10 / 8) and 6 in the hull, sabot loaded to start. After each shot the loader pulls
  the next round from the bustle with its blast doors open, rams, closes and arms: 5 to 6 s for
  an AI loader by skill. A player loader works it on the reload key: the second press inside the
  ram window gives a 4.5 s load, outside it 6.5 s. With no loader the commander, else the gunner,
  loads in 15 s and is off his sight meanwhile (no coax either). A damaged breech makes every
  load half as long again. The gunner picks the next round (fire mode); the round in the breech
  stays until fired or unloaded (8 s). Between fights the loader restocks the bustle from the
  hull, 12 s a round, with the turret to the front.
- **The bustle's blast doors**: a hit that sets off the bustle while the loader has its doors
  open is catastrophic; shut, the blow-out panels vent it as before.
- **The M242 25 mm's dual feed**: AP (M791, or M919 with that ammo package) and HE (M792)
  ready boxes of 70 and 230, switched in 1.5 s; single shot, low rate (100 a minute) or high
  rate (200). An empty box is refilled from the 600 stowed in 2 minutes by the gunner and a
  dismount, stopped and out of contact.
- **The TOW**: raised in 4 s at a halt (driving off lowers it), fired with the gunner holding the
  crosshair on the target to impact: the missile is wire-guided to his sight line (SACLOS) at
  about 190 m/s. Slewing the turret fast, smoke on the line, the launcher coming down or out of
  wire break the wire: a miss. Two on the launcher; a dismount reloads it from the five in the
  hull, launcher down, 45 s a missile.
- **The commander's M2 and the loader's M240** fire where their man looks; the commander can also
  fire the main gun and the TOW from his seat.
- **Shells in flight** (ShellFlight): gravity and drag tuned to docs/combined_arms.md 2.7.5's
  times of flight and drops (an M829A3 is 0.66 s and 2.1 m low at 1 km), hitting vehicles through
  the armour model with the distance flown, ricochets flying on, an HE or HEAT filling bursting
  on the people round it (not the crew under armour), a solid shot going through a man and on,
  HE craters in the ground and walls, fuzes that arm, self-destruct (25 mm HEI) and airburst.
  Every peer draws the round as a glowing streak.
- **Commander and loader seats** of their own kinds, and timed seat moves on the Abrams and
  Bradley: 3 s within the turret, 10 s to the driver's hatch (the Abrams' turret to the front),
  6 s from the troop compartment, at no job meanwhile.
- **Keys in a gun seat**: 1 the main gun (or the commander's or loader's gun), 2 the coax,
  3 the TOW; fire mode cycles the next round or the rate; reload is the loader's key, the feed
  switch, the launcher up or down, or a dismount's TOW reload. The HUD readout shows what's
  loaded and next, the racks, the feed and the launcher, and the loader's cycle ("RAM NOW").
- **maingun test suite** (CI and the default local list): the ballistics table, the turrets and
  their drives, the loader's cycle and short crews, the doors, the dual feed, every round fired
  500 m into STANAG-rated armour through ArmourModel and at people, the TOW and its wire, saves,
  budgets (50 shells in flight under 0.5 ms a step; a shot under 0.5 ms) and a late joiner.

#### Changed
- **Each gun on its own modules** (F-237): the coax no longer stops with the main gun's breech or
  barrel, only with its own sights; a damaged gun jams, a bent barrel scatters, per gun.
- The Abrams' commander and loader and the Bradley's commander are crew seats now, not passenger
  seats; AI still board them in the same order and casualties can still be loaded into them.
- Shell drag figures in data/shells.json retuned for the real flight (the A1 numbers were never
  flown); the TOW-2A and Konkurs-M are wire-guided.

### Inside the armour: modules, spall, crew hits and kill states (cg_brief queue item 2.1 (A2), armour/modules)

Combined arms phase A2: what happens after a round or blast gets through a vehicle's plate. Design:
docs/combined_arms.md 2.2 and 2.3.5 ("Built in A2" there says what's in); layouts in
data/vehicle_modules.json; every number Proposed; calls in docs/audits/followups.md "Calls made".

#### Added
- **Modules inside the Abrams, Bradley, AAV-7, M-ATV and MaxxPro** (VehicleModules): engine,
  transmission, tracks or wheels, fuel tanks, ammunition racks (the Abrams' bustle with blow-out
  panels and its hull rack, the Bradley's 25 mm and TOW racks, the AAV's Mk19 and M2 cans),
  breech and barrel, gunner's and auxiliary sights, fire control, commander's sight, turret ring
  and elevation drives, radio, driver's vision, smoke dischargers, external guns (CROWS, the
  loader's M240, the UGWS), compartments, the structure, and a crew station for every seat. Each
  is working, damaged or destroyed, and its damage does what docs/combined_arms.md 2.2.2 says:
  slower or stopped (engine, transmission, a thrown track, run-flat wheels and a third gone),
  leaks, emptied tanks and fires, guns that won't fire, jam or scatter, a dark radio (the Blue
  Force Tracker loses it), slowed or hand-cranked turret drives.
- **The path through the vehicle**: a round, rod or shaped-charge jet that beats the plate
  goes on along its line through the modules in order, each taking its share by the residual
  left and eating some of it (a jet spends itself faster than a rod), until nothing is left. A
  crewman on its line is struck through his real hitboxes (lethal: a rod, jet or 12.7 mm+). A
  bullet that gets in keeps only what the modules leave it before Ballistics carries it into the
  cabin.
- **Spall**: a cone of fragments behind the hole, more and wider when the plate nearly held,
  cut 60% (and narrowed 40%) by a spall liner (Abrams, Bradley, MRAPs; the AAV's kit). Each
  fragment stops in the first module or man it meets: a fragment wound through the wound model,
  his body armour checked as for a grenade's. This replaces "everyone within 2.5 m of the hole".
- **HE inside**: a filling that gets in (HEI, HE-FRAG, thermobaric, HE punching a thin plate)
  bursts behind the plate: overpressure on the modules near it, blast, lethal zone and fragments
  on the crew in the compartment. HE and stopped shaped charges on the outside wear the external
  modules near the burst (tracks, wheels, optics, guns, smoke boxes).
- **Ammunition**: a rack that's damaged loses rounds; one destroyed rolls to go off (the 2.10.2
  table): the Abrams' bustle vents through its blow-out panels and the tank fights on, the 25 mm,
  Mk19 and M2 stowage cooks off in a fire, the Abrams' hull rack and the Bradley's TOW rack go up
  (a catastrophic kill).
- **Kill states** on every vehicle, replicated and saved: mobility, firepower, crew, knocked out
  (and whether it's repairable), catastrophic. `Vehicle.modules.kill_state()`, the
  `kill_changed` signal and `server_bail_out()` are there for the AI crews (A9).
- **Belly blasts become crew injuries**: a mine or IED under the hull puts what reaches the crew
  floor (by the same sum the STANAG 4569 mine ratings are proven with) on every man aboard. At or
  below what the floor holds they come away with ringing ears and fight on; past it, broken legs
  and spines, then deaths. The wheel or track station over a big charge is destroyed, and what
  sits on the floor takes it (the AAV's fuel under its troops). The mine ratings were rechecked:
  every vehicle's stored rating still holds, and armour_test now proves the crew stay able at it
  and are hurt one level past it.
- **HitEvents**: every resolved hit goes to every peer (outcome, plate, modules hit and their
  states, crew hit, kill states); the last 10 are kept on each for the x-ray (A5).

#### Changed
- A wheeled armoured vehicle with wheels shot out now runs on its run-flats (x0.75 each, two at
  most) and a third stops it, in place of crawling at 15% on every rim. One thrown track stops a
  tracked one (it was both).
- Launcher jets into the Abrams, Bradley, AAV-7, M-ATV and MaxxPro no longer use the flat 3 m
  kill line behind the plate: the modules trace the jet. Technicals, helicopters and static
  weapons take hits on their old zones exactly as before.
- The old hit zones (`Vehicle.zone_health`) are answered from the modules on those five, so
  repairs, the motor pool, the HUD readout and the AI's "it can't go on" read the same as before.

### Armour standards: STANAG 4569 for vehicles, NIJ 0101.07 for body armour (cg_brief queue item 2.0, armour/standards)

Captain, 2026-10-22: "make sure it follows the current standards for armor". Design and tables:
docs/combined_arms.md 2.4.7; numbers in data/armour_standards.json (all Proposed); calls in
docs/audits/followups.md "Calls made".

#### Changed
- **Body armour is rated by NIJ 0101.07** (2023) in place of 0101.06: the ladder is HG1, HG2,
  RF1, RF2, RF3 (then .50 BMG above everything). Every plate, helmet, vest, exo pad and round is
  re-rated: IIA and II became HG1, IIIA HG2, III and III+ RF1, III++ RF2, IV RF3. Item names,
  descriptions, the inspect panel ("Rating: NIJ RF1", and now "Soft armour: NIJ HG2" on vests),
  the armory and loadout editor and the armour readout ("Front RF3 64%") show the new names.
- **What hits now do differently** (only where the new threat lists say so; everything else is
  as before):
  - HG1 armour (the old IIA light vest, bump, PASGT, SSh-68 and M1 helmets, the 6B23's soft
    armour) now stops **.357 Magnum, 9 mm +P+, 7.62x25 Tokarev** and the other old level II
    rounds: 0101.07's HG1 is tested against .357 Magnum.
  - RF1 armour (the old III plates: light and medium PE, AR500, the ECH and Altyn helmets, the
    HX-1's belly plate) now stops **7.62x39 mild steel core (AKM, RPK), 7.62x51 M80 ball (M240,
    SCAR-H, M110), .303, M118LR and 6.5 Creedmoor**: 0101.07's RF1 list has M80 and 7.62x39
    MSC with M193. This ends the old swap that kept 7.62 ball above the light plate. M855 and
    7N6 close in still go through RF1, and still drop to RF1 below 700 m/s.
  - The old III+ plates (SAPI, UHMWPE III+) are RF1 and stop exactly what they did; III++ (steel,
    side plates, heavy helmet, exo pads) is RF2 and stops exactly what it did; IV is RF3, same.
  - The SAPI and UHMWPE plates now share RF1 with the PE and AR500 plates (they differ in
    weight, durability and fit), so an AI scavenger no longer swaps an old III plate for a III+
    one (Scavenge weighs a piece by its step on the ladder times its integrity: the ladder has
    six steps now, not eight).
- **Old saves and mods load as before**: saves hold item ids, never ratings, so old kits get the
  new ratings from data; any rating, soft rating, visor rating or weapon "threat" stat that still
  says IIA-IV reads as its 0101.07 level (Ballistics.level_name, LEGACY_LEVELS).
- **MaxxPro belly blast share 0.15 to 0.13 and BUSK III's 0.2 to 0.18** (not used in play until
  phase A2): so they meet mine 3b and 2b. **M-ATV appliqué** now also covers the rear (+10) and
  roof (+4) and weighs 0.8 t, so it meets KE 3 all round.

#### Added
- **STANAG 4569 ratings on every vehicle and armour package** (data/vehicle_armour.json
  `stanag_ke` per arc, `stanag_artillery`, `stanag_mine`; a package's own replace the base's):
  Abrams KE 6/4/3 (front above STANAG: its RHAe figures stay), artillery 6, mine 2a/1 (TUSK 4a/1);
  Bradley 4/3/3, 5, 2a/1 (BUSK III 4a/2b); AAV 3/3/3, 5, 1; M-ATV and MaxxPro 2/2/2, 4, 4a/3b
  (appliqué 3/3/3, artillery 5); technicals 0; aircraft and crew-served weapons not rated.
  `ArmourStandards.text()` gives one line ("STANAG 4569 KE 2, artillery 4, mine 4a/3b") for the
  HUDs to come.
- **A MaxxPro appliqué package** (0.9 t), as the M-ATV's.
- **Fitted packages' bolt-on armour counts in hits**: `ArmourModel.with_packages` adds a
  package's `plates_add` to the plate a round meets (the appliqué; packages are fitted from A8).
- **Tests**: armour_test proves every vehicle's and package's ratings from its plates and belly
  (each level's threats stopped at its range over the arc, the next level's through somewhere;
  426 checks) and that the tier rule never lets KE 1's rounds into a rated crew zone; armor_test
  fires each NIJ level's threat list at its velocity and range at every rated plate, helmet, pad
  and vest (and the next level's list, at least one through), and reads old names.

### Render pass: cities and soldiers (Captain, 2026-10-22: v0.5.4's frame rate "unbelievably bad")

#### Fixed
- **Stutters everywhere after the cities came in (v0.5.3 on).** Near a city, its twenty blocks all
  loaded as full-detail voxel buildings at once, which ran the graphics card's buffers out; from then
  on every new mesh in the game failed and logged an error, hundreds of thousands of them, and the
  game crawled, menus included. Now only the nearest few sites (5 at High, 6 at Ultra) are full
  voxels at once; the rest stand as their plain stand-ins, as distant sites always have.

#### Changed
- **Far soldiers are lighter to draw.** Past 50 m (High) a soldier is drawn from a 1 cm copy of his
  0.5 cm model (about a quarter of the triangles), and past 80 m he casts no sun shadow (was 150 m).
  Ultra keeps every soldier at full detail with shadows at any range.
- **World detail at distance** (Settings, Video) now also sets these: how many sites are full voxels
  at once, and the soldiers' detail and shadow distances.
### Performance: cghath's world content (perf/world-content)

> **Where I stopped (2026-10-23):** done, numbers in docs/performance.md ("cghath's world content").
> CI 60 Hz frame cost, average / 95th ms, claude/ai-driving 78dc9a17 -> this branch 7a92356a: town
> 7.5 / 15.3 -> 6.0 / 9.5, city 112 / 127 -> 83 / 95, woods 8.3 / 12.3 -> 5.8 / 8.6, drive 8.4 / 11.6
> -> 6.7 / 10.0, heli 10.2 / 18.3 -> 5.9 / 8.2, no hitches in any of them; townperf's tick 12-16 ms
> (budget 20). Quiet local, back to back (R0582 -> R0583): heli 14.4 / 23.9 -> 10.7 / 16.0, city
> 143 / 203 -> 137 / 153, the rest within noise. Local suites: smoke, terrain, heliflight (R0571,
> R0574), townperf's checks and city (R0578), perfcases (R0583); forest's one failure ("nothing went
> into the campaign") fails on claude/ai-driving's CI too. Next: F-230 (soldiers against the city's
> voxels), F-231 (a look at the async navigation map in a city fight), F-232 (draws).

#### Changed
- **Terrain and scatter build on a worker thread** (F-225): a fine terrain chunk's vertices and
  ground colours (22-32 ms of main thread each) and a scatter cell's near-tier ground cover (27-35
  ms) are worked out on a worker, one at a time, and only the mesh is made on the main thread: no
  more hitches from the ground and the tufts coming in round a vehicle or the UH-60. A cell's ground
  cover is laid on the ground as generated (a crater made before the cell was built no longer lowers
  its tufts).
- **Navigation**: the zone's navigation map builds its iterations on a worker (a city's updates were
  10-16 ms on the main thread, twice a second); which chunks the soldiers want is worked out with
  plain floats and the chunks to drop looked for every fourth pass (5-40 ms a pass for a city's AI);
  no chunks are baked round a soldier in a helicopter flying faster than 8 m/s or higher than 15 m
  (from a UH-60, 20-25 bakes a second).
- **Helicopters**: contour flight's look-ahead points 2 s and further ahead are worked out every
  third tick in turn (~2 ms a tick a helicopter).
- **Grass carpet**: not laid or drawn with the eye more than 10 m over the ground (a helicopter at
  its contour height, a high window): its lays were 12-30 ms frames from the UH-60.
- **Animals**: only those that walked move their hit box and their place in the herd's MultiMesh.
- **perfcases**: budgets tightened (town 15 / 25, city 200 / 300, woods 18 / 26, drive 18 / 26, heli
  18 / 30 ms, 15-30 hitches a minute; fight's times unchanged, its hitches 70 -> 90 a minute, the
  AI's ticks and team spawns that failed claude/ai-driving's own CI); it prints each case's navigation bakes, map
  updates and the navigation server's frame, and waits up to 180 s for a case's modules (CI's city
  block still building at 60 and 100 s). FrameCost counts "nav_wanted" and "nav_start".

### Income: ways to make money with the flow of the game (claude/income)

> **Where I stopped / next step (2026-10-22, 22:15 CDT):** done: all 4 income streams built, the
> 40-campaign economy sim re-run with them and tuned (before/after in docs/economy.md: careful
> $430k -> $677k, median $329k -> $514k, sloppy still in debt). Next: CI on claude/income, merge into
> claude/ai-driving for v0.5.4, a look at the Side work page in game. Design and
> numbers: docs/income.md, data/income.json (all Proposed). Sim: tools/economy_sim.gd --income 0|1. Local: income (R2531, R2536), smoke + ui
> (R2532), contracts (R2537), base + ui (R2538), income (R2541, R2543), smoke + base + ui (R2542, R2544).

#### Added
- **Side jobs for the high command squads** (docs/income.md 1): employers and fixers post jobs
  (escort a client, guard a site, train locals, run a supply route) on the base screen's new
  **Side work** page and as a line on the contract board (**Side work [J]**). Send Hawk 2 or
  Viper 3: a quarter of the pay up front, the rest when they come back. The squad is away for the
  job's days and can't deploy with you. The job is settled off-screen by a risk roll on the
  squad's skill, kit, morale and fit men against the zone's danger in the living war; pay rises
  with the danger. Every Send button shows the odds of trouble, of losing a man and of failing
  before you commit. Squads can come back wounded, a man short, or without the job done. They
  report on the company net and leave a debrief card. Training locals raises rebel support.
  Squad morale is new and saved.
- **Captures sold by standing** (docs/income.md 2): captured vehicles and heavy guns in FOB
  storage sell to Mama Rook, Halloran, US Forces or (guns and technicals) the Highland Front.
  Each pays by its rate and your standing with it, each has a standing floor and its own effects.
  Or have a high command squad deliver one for a quarter more, at the side job's risks.
- **Bounties on the war's leaders**: every faction leader still free carries a bounty, posted by
  the lawful employer at war with them and worth more while the faction is strong. Paid at the
  debrief: in full for an HVT capture or manhunt, 0.6 for an HVT kill and only with his ID
  papers carried out. HVT kills now name a leader too.
- **Intel to the right buyer**: the debrief's buyer list shows each buyer's price and standing
  effect. Lawful forces pay fair, fixers more, a rival of the faction it's about more still (the
  lawful factions hear of it), and the faction itself pays most to have it back.
- **FOB businesses** (docs/income.md 3): with a FOB, open convoy security, a militia training camp
  (raises rebel support), checkpoint tolls (by the roads you hold) or motor pool rentals (by the
  vehicles at home). Each has a setup cost, daily upkeep with its local staff, and supplies from
  the FOB's stocks, and pays daily. Raiders threaten them as the war comes near: a protection
  contract goes on the board; leave it and the business is raided. Lose the FOB and you lose them.
- **Black market trading** (docs/income.md 4): buy fuel, weapons, medical supplies and contraband
  where they're cheap and sell where they're scarce. Markets are your home region, the region of
  your last job, and the fixers who'll deal with you. Prices follow the war (fronts, who holds the
  ground). Selling a lot in one market drives its price down for a few days. Cargo rides in the
  trucks, more with each vehicle. Contraband can be seized with a fine and US standing, and
  crates of weapons get noticed.

#### Changed
- **Economy sim with the income streams** (docs/economy.md, `--income 0|1`): the profiles send
  squads on side jobs, sell captures to buyers, hunt bounties, open businesses once they have a
  FOB, protect them or not, and trade. Tuned on its results (all Proposed): side job pay
  $7-11k by kind with a rest day, business upkeep down and pay up, bounties $15-20k by role,
  market spread 8%. 35 days, 40 campaigns: careful $430k -> $677k, median $329k -> $514k (none
  broke), sloppy -$176k -> -$61k less loans (12 of 40 out of credit, from 16).

### Voice and economy (claude/voice-economy)

> **Where I stopped / next step (2026-10-22, 19:50 CDT):** both parts built and pushed. Local:
> smoke, voice (R2527), contracts (R2526) and roles (R2529) pass. Not yet: CI on the branch,
> merge into claude/ai-driving, a look in game (no windows while the Captain plays).
> Next: render the 81 new lines with Piper when it's on a PC (tools/voices/lines_to_render.txt,
> docs/voice.md), wire a speech recognizer to `VoiceOrder.run`, and price armour packages into
> the sim once phase A8 has them. Every number is Proposed.

#### Added
- **Context-aware barks** (docs/voice.md): Grenade! (the side it threatens, before it goes off),
  Check fire! (friendly on friendly), enemy down by what he was ("Gunner down!", "RPG's
  down!"), pinned with where the fire comes from, out of ammo, and confirmations for voice
  orders. Enemies say them in their own tongue, unsubtitled.
- **One voice at a time per group**: a squad's lines wait their turn unless they outrank
  what's being said (0.6 s; `Callouts.PRIORITY`: man down, grenade, check fire and the medical calls
  cut in; contact, enemy down, pinned and out of ammo next; the leader's calls, reloading,
  moving, set after).
- **Voice orders**: more of the command menu (follow me, bound, garrison, clear the town, flank,
  assault, suppress, watch, stance, mount up, get out); a squadmate's callsign or "everyone"
  before the order; the one ordered confirms ("Holding."); the high command squads by callsign
  ("Hawk two, move there on alpha": move, hold, defend, follow, regroup, extract, attack, base
  of fire, bound, fall back, report); go codes ("alpha go", "execute H hour").
- **Clips to render later**: `tools/voices/gen_callouts.py` has the new lines (English, and the
  enemy barks in Russian and Farsi), renders only clips that are missing, and `--list` writes
  what's left (tools/voices/lines_to_render.txt: 81 lines, 720 clips). Subtitles meanwhile.
- **Economy sim** (tools/economy_sim.gd): the standing high command squads, heli insertions, a
  scripted expensive op, 5-day checkpoints; `curve()` and `op_result()` for the tests.

#### Fixed
- **Squad spacing** (`SquadAI._apart`): the formation slots kept between ticks (perf-towns) could
  still list a man freed since; the loop's typed variable threw "previously freed instance"
  every tick (roles suite).

#### Changed
- **Economy pass** (docs/economy.md, all Proposed): the standing squads' men get their own
  field rate ($250 a day, `operations.hc_per_head_day`); field costs $700 -> $550 a head a day;
  contract pay by rating 0.35-0.95 -> 0.46-1.22; support calls about 15% cheaper; a heli
  insertion costs $6,000 (it was free); death benefit $10,000 -> $8,000; treatment $1,200 ->
  $900; respawns $3,000 rising to at most $6,000. Sim, 35 days: careful $110k -> $430k, median
  -$3k (9 of 40 broke) -> $329k (none), sloppy -$413k -> -$53k (16 of 40 broke); an expensive
  op won -$56k -> -$13k, failed -$101k -> -$70k.

### Perf: towns, cities and the heli (claude/perf-towns)

> **Where I stopped / next step (2026-10-22, 18:50 CDT):** three batches pushed (c570c558 + docs).
> Quiet-machine 60 Hz frame cost avg / p95, R2513 -> R2523: city 136 / 196 -> 103 / 226, fight
> 62 / 95 -> 35 / 50, woods 25 / 34 -> 14 / 21, drive 16 / 28 -> 8.5 / 13, heli 15 / 31 -> 10.6 / 19
> (hitches 27 -> about 3 a minute), town (a village now) 8.8 -> 9.2. perfcases budgets tightened
> and pass locally (R2523); smoke, world, props pass (R2520); townperf passes (R2522; R2520's miss
> was a busy machine). Not yet: CI on the branch, merge into claude/ai-driving.
> Next: team spawns made virtual or woken a few a frame (F-206), a scatter cell's and a terrain
> chunk's single build (F-225, cghath), soldiers' draws (F-226), the city's patrols' movement.

#### Changed
- **perfcases** has a **city** case: the Old Quarter's city, walked up its middle street from
  outside. **town** is now the zone's biggest town or village outside the city (it used to pick
  a city block once the city came in). The profile splits the AI's act and think by part.
- **Casualty care**: who answers a casualty is kept for a quarter second while that one is still
  free for him (every AI's think worked it out for every casualty; 9 ms a think in the city).
- **Formations**: a squad's slots are kept four ticks while its lead stays within 0.6 m and keeps
  his heading (a few rays a man, worked out again for every man that asked).
- **Building scans** (F-206): a cold scan's grouping stops at the frame's budget between buildings
  and between stair paths and goes on at the next ask (100-250 ms in one frame in a city block).
- **Casualty care** (2): which medic a carer's call goes to is kept the same way.
- **AI paths**: a destination that moved under 15% of the way left (up to 3 m) keeps its path until
  the next re-plan; formation slots of an AI squad are kept 8 ticks and through small turns.
- **Follow-in** (F-211): no building scan when the squad has nobody to send in.
- **perfcases budgets** tightened: town 30 / 50, city 260 / 520, fight 100 / 170, woods 35 / 50,
  drive 40 / 60, heli 40 / 70 (average / 95th, ms).
- **Grass** near the camera: one buffer write a lay, only the points that can be in the circle,
  new tufts limited by time, and an unfinished lay goes on from the points it left (from a
  helicopter it went through the whole circle again every frame).

### Mission UI pass (claude/mission-ui)

> **Where I stopped / next step (2026-10-22, 22:39 CDT):** all four screens done and pushed
> (board, briefing, objectives tracker, debrief) with the flow between them. Local runs: R2510 (smoke, contracts, missions PASS; ui's one red was the board's open help at 1280x720 @2.0, fixed in f869ce82), R2511 (smoke + ui PASS at f869ce82).
> Next: CI on the branch, then a look in game (no windowed screenshots while Captain plays):
> the glance strip's wrap on the briefing panel at 1.5-2.0 UI scale, and the hotkeys against
> the map's own keys (V, L, R, G only fire while the briefing panel shows). Numbers Proposed:
> ContractGlance INTEL_GOOD 0.8, INTEL_FAIR 0.6, RISK_HIGH 4.

#### Added
- **The job at a glance** (scripts/ui/contract_glance.gd), the same on the board, the briefing
  and in the tests: pay and its split, risk (and the real threat once it's out), the enemy
  estimate, intel quality, night and weather, the employer and the company's standing with it,
  days and any time limit, the supports allowed with the budget, and how many high command
  squads the job allows. Hover any figure for what it means. A contract kind of its own (the
  operation contracts) adds figures by carrying "glance": no UI change needed.
- **The mission flow** as a row of steps over each screen: Board > Prep > Brief > Deploy >
  Track > Debrief, the current one lit.
- **Hotkeys printed on buttons** (UiKit.hotkey: Godot shortcuts, so typing in a field never
  fires one). Board: A accept, P prepare deployment, R renegotiate, X abort, S shop, L loan,
  W wait a day, Shift+W a week. Briefing: V the 3D look at the plan, L last plan, R ready,
  G start. Debrief: C continue, B claim best value.
- **Last choices remembered** (settings "mission_ui"): the board's terms and the contract last
  picked, the briefing's helicopter drop, approach and supports ("Use my last plan"), the
  debrief's salvage sort.
- **Debrief: pay and deductions, explained.** Each contract's verdict lit green or red; the
  advance, completion, bonuses, pay held back and advance clawed back, fines, expenses and the
  net, each with its reason; a Deductions figure. **Standing and the war:** each faction's
  change and where the company stands with it now, the locals, and what the job did to the
  living war (a zone's grip weakened or changed hands, a front moved, a leader taken), recorded
  into the debrief as it happens (Contracts.war_lines).

#### Changed
- **Contract board:** opens on a contract (the held one waiting to deploy, else the first
  offer), the picked contract's next step first and lit (Accept, or Prepare deployment once
  it's held), Enter on a row goes to that step, and after accepting it moves on to the signed
  contract. Abort and loans ask first. Host messages light up for a moment. Bonus and optional
  objectives are tagged in the briefing text.
- **Briefing panel:** the glance figures under the title, bonus and optional objectives tagged,
  "Look at the plan in 3D" right after the objectives as the next step (it says "Back to the 2D
  map" while open), "None allowed on this job" when no supports are, and "N of M ready" with
  Start saying who it waits for.
- **Objectives tracker:** the heading counts the required objectives done ("2/3 done"); a live
  objective says which way and how far it is from you ("NW, 340 m"); bonus and optional ones say
  so; within a contract live ones come first, then done, then failed.

### 3D loadout editor and armory (claude/loadout-3d)

> **Where I stopped / next step (2026-10-22, 16:05 CDT):** done and pushed: saved kits and
> mounts (host ops), the 3D editor (scripts/ui/loadout_editor.gd + loadout_preview.gd), the 3D
> armory (scripts/ui/armory_room.gd), opened from the base screen; design in docs/loadout_3d.md.
> Local runs: loadout R2506, base R2507, ui + smoke R2508, all PASS. Next: CI on the branch, then
> a look in game (no windowed screenshots were taken while Captain plays): marker placement on
> the female build, gun rail markers, shelf spacing.

#### Added
- **3D loadout editor.** Your soldier full size in 3D: his own model, camo, face and the voxel
  kit, drawn by the same code as in the field. Drag to turn him, the wheel zooms, 1-5 focus the
  head, torso, legs, weapons or the whole body. Markers on the model are the slots: the helmet
  and its NVG mount, carrier, plate pockets, every MOLLE point, the pack, the guns with their
  optic rail, muzzle, underbarrel and side rail, and the pockets. Click one and the picker lists
  everything that fits, owned or not; unowned items show their price. Picking puts it on the
  model at once as a draft, and an unowned pick offers "Buy now" with its price and your cash.
  "Buy missing: $X" (B) buys everything the draft lacks and fits it; Apply (Enter) fits the
  draft from the stash under the usual rules (litres, kg, bulky items, plates in pockets).
  Undo (Ctrl+Z), Revert (R), Last applied (L); closing with changes not applied asks first. The
  stats panel shows weight and load tier, litres, protection by NIJ rating, ammo carried and
  speed. The last person, kit and target you picked are remembered.
- **3D armory.** A room with the company's gear on shelves by kind (weapons, optics, armour,
  packs, pouches, ammo, medical, grenades, the rest), every item as its voxel model. Point at
  one for a panel with its price, stats and how many the company owns; buy it there (B), or Fit
  on me (F) or drag it onto your soldier to open the loadout editor with it fitted. It reads the
  existing stash, shop and quartermaster prices; nothing is forked.
- **Saved kits.** Name and save a loadout; it goes with the campaign and every player in co-op
  sees the same list. Apply a kit to yourself, a squadmate, a fire team, everyone in a role, the
  whole squad or a high command squad (Hawk 2, Viper 3). It becomes their standing loadout too,
  so Restock refills to it. "Buy missing" buys what all of them lack in one go, priced as one
  total. Fire teams are the picked squad in fours (Proposed); at most 40 kits (Proposed).
- **Weapon mounts and the helmet's NVG are part of a loadout.** A gun's suppressor, grip, light
  or laser and choke, and the NVG on a helmet, are recorded with the kit, refilled by Restock
  and taken from or put back in the stash like an optic.

### Terror groups that grow (docs/ai_tactics.md section 7)

#### Added
- **Factions have men, weapons and money.** Each terror group's money comes from the zones it
  holds, and it spends that money on recruits and their weapons. It loses men to kills, lost
  zones and contracts the company wins against it. What it can field follows from its armed
  men: cells, teams, squads, platoons, then companies. State forces (the US and its allies,
  Eastern Concord) field full units from the start.
- **Their size shows in the zones.** Garrisons and the enemy commander's reserves grow as a group
  grows and shrink as it loses, so a bigger group sends more patrols and hunter teams. Those
  stay pairs and teams of 4-6. Everything stays as before at each group's starting size.
- **Small but dangerous.** A group down to cells and teams is its hard core: veterans who lie in
  wait more and hit and run instead of standing to fight.

### Platoon, company and brigade tactics from the reels (docs/ai_tactics.md, the AI commander)

#### Added
- **Bunkers and trench lines by SOSRA.** The AI commander takes a fortified objective in the
  reels' order. It suppresses the position, smokes its ports, sends a group to secure the far
  flank, makes a breach with its engineers, and only then assaults through the breach.
- **Isolate before the assault.** Against a village held in strength, the commander fixes it with
  fires and sends small teams to cut the ways in. It starves the garrison until it's half
  what it was, then attacks from every axis at once.
- **Feigned retreat.** One group attacks, then pulls back. If the garrison follows it out, a
  second group waiting out of sight on another side goes in.
- **Defence in depth.** A defending side puts a security zone a kilometre forward. Recon groups
  there call fires on what they see and pull back before they're caught.
- **Brigades.** Several company plans run under one command element. The element keeps a
  reserve company, and a company that stalls gets the brigade's fires first, then the reserve.

### Team and squad drills from the tactics reels (docs/ai_tactics.md, every side)

#### Added
- **Near ambush.** A squad hit from under 35 m while moving doesn't look for cover in the kill
  zone. Its gun and one man fire flat out, the rest throw frags, and 2-3 seconds later they
  charge through the ambush line. Then they consolidate facing back.
- **Break contact as a drill.** Smoke from the grenadier first. Then the man furthest back goes:
  "Moving!", to the rally point, "Set!". Then the next, each covered by those still firing, until
  all are set at the rally point facing the enemy.
- **Rally points.** On the move a squad names a rally point every 150 m, about 45 m back the way
  it came. That's where it breaks contact to.
- **Fire superiority first.** Flankers wait in cover until their base of fire is shooting:
  "Base is set, move!"
- **Sectors of fire.** A base of fire spreads its guns across the enemy and past both flanks,
  never all on one man. It shifts its fire beyond the objective as its flankers close in, and
  stops when they're on it.
- **Assault lanes and consolidation.** Assaulters go through the position in their own lanes, to
  a limit just past it. Then they take all-round security and check their ammo.
- **Contact reports** say how many and what: "Contact, two o'clock, 80 m, three men, MG".
- **Cleared buildings** get a chem light at the door when someone carries one.
- **Terror groups fight their own way.** Jihadists press and stay, guerrillas hit and run, and
  cartels hold what they guard.
- New test suite drills, in tools/run_tests.sh and CI.

### Requests that get done (combined arms phase B4, part 2)

#### Added
- **Allied units carry out what they accept.** Ask an allied unit through the contextual menu
  (look at it) for suppression, covering fire, smoke, a hold, ammo or a medic. It moves into
  range if it has to, does the job, and the request card follows it: on the way, on station,
  done. Units under the AI commander do it through their orders. A unit without what you asked
  for says so.
- **Check fire** is on the contextual menu over open ground.

### Deconfliction: no blue on blue (combined arms phase B5, docs/combined_arms.md 4.5)

#### Added
- **Check fire.** Any player can call a check fire on a point. Every friendly gun firing within
  100 m of it stops for 30 seconds.
- **Lanes.** Each allied group's task gets its own lane, kept clear of the other groups' lanes.
  Allied groups don't shoot across another group's lane, and their moves bend round players.
- **Player bubbles.** No allied suppression lands within 100 m of a player.
- **Fire missions near friendlies.** The fire direction centre warns before rounds land near
  friendlies ("Splash in 45, friendlies stay south of the target"). It checks fire if one walks
  into the target area.
- **Vehicle gunners** don't fire near friendly vehicles.
- **Friendly-fire incidents** are logged for the debrief.

### Armour and infantry together (combined arms phase B3, docs/combined_arms.md 3.6)

#### Added
- **Tanks keep their infantry.** Each allied armour section is paired with an infantry group and
  moves with it by the ground. In the open it overwatches the objective from a kilometre off. In
  woods it follows 150 m behind, and in a town 75 m behind. It waits at a town's edge until its
  infantry is in.
- **Target hand-off.** Infantry held up by a machine gun or a gun position marks it to its tank
  ("Anvil 1, Saber 2, MG at 041 053, 120 metres, my tracer."), and the tank puts fire on it.
- **Armour asks for infantry.** An AT team reported near the armour sends its infantry after it,
  and the tank calls for help on the net, asking a nearby player when its infantry is busy.

### The AI commander (combined arms phase B2, docs/combined_arms.md 3)

#### Added
- **A commander for each side.** It sees only what its side has reported. It knows its groups
  by their sitreps and tasks them through the same orders high command uses: assault, support by
  fire, flank, recon, reserve, screen and defend. Every 20 s, or at once when something changes,
  it scores each group for each job by how suited it is, how fit, how far away and how free. An
  assault is never sent without its support by fire, and no group without anti-armour weapons is
  sent at known armour. Each decision is logged with its reason.
- **Timing.** An assault waits at its attack position until its support by fire is set, or
  2 minutes, then goes ("Hammer 1 is set." "Saber 1, go."). An objective counts as taken after
  90 s with no reported enemy in it. A phase moves on when every objective in it is taken.
- **Reserves and stalls.** A quarter of the side's strength is kept back. It goes in when the
  main objective stalls, an assault goes amber, a counterattack is seen, or to exploit a quick
  win. At the phase's limit the commander shifts the main effort or calls fire support and
  pauses.
- **Falling back.** An amber group holds and asks for help. A red group breaks contact to its
  rally, and two red groups of a kind merge there. A side that loses half its men pulls back.
- **Defence and counterattacks.** A defending side holds its sites and keeps a mobile reserve.
  A lost site is retaken only by a force three times what's seen there, with anti-armour weapons
  if armour is there; otherwise it's contained. The force assembles out of sight and goes in 5-12
  minutes later, after a preparation. Players hear it coming if their side has reported the
  enemy massing.
- **Off-screen fights by armour.** A tank shrugs off rifles and an AT team hurts it, also when
  both are virtual.
- Hot zones keep their enemy commander's rules unchanged; the new commander sits beside it.

### High command (combined arms, phases C1 to C6)

> **Where this lane is:** C1-C6 done on claude/ca-c-high-command (B1 and B4 part 1 merged in).
> The C lane is complete; follow-ups are in docs/combined_arms.md section 10 (C2.11, C4.9, C6.7).

#### Added (C6: contextual menus)
- **One key does the obvious thing.** Look at something and tap the middle mouse button: the top
  option for it happens (a squadmate follows you, a casualty gets treated, an enemy gets tagged,
  an allied squad gets asked for suppression when you're in contact). Hold the button for a radial
  with the rest and "More..." (the full command menu). A prompt under the crosshair says what the
  tap will do. The options you use most come first next time.
- The interaction menu (Left Ctrl) on a squadmate now has Follow me, Hold here, Heal up and Give
  ammo.
- The map's order bar puts the orders that fit what's under the cursor first (an enemy marker:
  Attack and Support by fire), and the ones you used there last.

#### Added (C5: the 3D high command camera)
- **Shift+M lifts you into a 3D view over the zone** (or "3D view" on the map's high command panel).
  WASD or the screen's edges pan, the wheel zooms from 40 m to 1,500 m over the ground, middle-drag
  orbits, Q / E rotate, F frames your squads, a click selects a squad and a double-click follows it.
  Your squads stand on poles with their callsign, strength and state, their orders drawn on the
  ground; enemies show only where your side has reported them, with how sure that is. Soldiers and
  vehicles themselves aren't drawn, so the camera can't scout. Give orders with the map's keys.
  A hit drops you back into your body; a near miss reddens the edge.
- **The 3D mission map.** "3D map" on the briefing shows the zone in relief with the objectives,
  insertion points and known enemies standing on it: tilt, zoom and orbit the plan.
- Command mode on the map now toggles with C (Tab is the theatre map).

#### Added (C4: the map-order HUD)
- **One way to give every order on the map.** Select a squad (click its frame, Shift to add,
  drag a box, or 1-4), pick the order on the bar along the bottom (each button shows its key and
  explains itself; the ones that fit what's under the cursor come first), click the point, drag
  to face, release. The ghost says what's wrong ("Off the map") before you commit; the line goes
  dotted until the squad says "copy". Shift queues, right-click cancels, Backspace cancels the
  squad's order, Ctrl+Z undoes the last one within 10 s, Space repeats the last order, Tab turns
  command mode off.
- **Place the gun with its cone of fire.** G, then drag its facing and roll the wheel to widen or
  narrow the arc. The cone shows what the gun can see in green and the dead ground behind crests
  and buildings in dark, a red edge where a bank close in blocks it, range rings, how high it sits
  over the ground it covers and how many known enemy positions can see the spot. The team sets up
  facing the middle of the arc and fires only inside it.

#### Added (C3: Phase 2)
- **Real high command orders.** Attack (to an attack position, then in; "objective secure" once
  it's quiet; it falls back if it's spent), Support by fire (never with a friendly in the line of
  fire; fire shifts deeper or lifts when friendlies close on the target: "check fire, friendlies
  on target"), Bound, Fall back, and Defend a frontage (a sector per buddy pair).
- **Go codes.** Give an order "on Alpha" (the map panel's "Next order" picker) and it waits; Attack
  and Support by fire move to their position first ("Hawk 2, set. Ready on Alpha"). The panel's
  Go buttons show how many are waiting; H-hour orders go with the deployment.
- **Requests.** A squad past its casualty limit asks to break contact. Approve or deny on the map
  panel or with Shift+Y / Shift+N; unanswered after 20 s, the hero decides.
- A squad that loses its leader goes quiet for a moment until the new one has the radio.
- A HUD line while hero squads are out: "HAWK 2 ● green Set | VIPER 3 ● amber Contact", with the
  latest request and its keys under it.

#### Added (C2: Phase 1)
- **Two high command squads from the start.** Every new campaign has Hawk 2 and Viper 3 on the
  roster: four men each (a team leader with a record, an autorifleman, a medic and a rifleman) in
  their own kit, on wages, with 14 days of their wages added to the start cash. They deploy on
  every contract beside the player squad (100 m to either side of the insertion) and never take
  a player-squad slot. "Squad & deploy" lists them with a "Deploys" box to leave one at home and
  their callsigns to rename.
- **Ordering them.** Right-click the map: Move, Defend (a building near the point is garrisoned,
  else a line facing the threat), Regroup, Extract, Hold, Follow me, Support me, Report, Cancel.
  Shift queues. Every order is acknowledged, then ends done, failed with a reason ("unable: no
  route to 041 053. Holding"), or cancelled; a squad that stops making headway says "held up" at
  30 s and gives up at 90 s.
- **The company net.** Squads report on it in their own subtitle lines: copy, set, done, contact
  (with an intel marker; the other squads hear of it 3 s later), man down, a new leader taking
  over when the hero falls, and sitreps. The map shows each squad as a frame with its callsign,
  strength and a green/amber/red pip, its order as a line, and a panel with each squad's card and
  the net.
- **Allied elements report too.** Their orders now have the same lifecycle and net lines.
- One commander at a time (the host by default; "Take command" on the panel). Contracts carry
  how many squads they allow (2, more on rated-5, hot zones and operations).
- Hero squads inside the extraction point come out with you; the leave-behind warning names any
  that aren't.

#### Added
- **A second friendly squad no longer breaks the first.** The groundwork for hero-led squads
  (docs/high_command.md G1-G12): a squad beside the player's keeps its own men, orders, picture and
  voice. Each of its men carries his group (`Soldier.hc_id`), and `HighCommand.server_spawn_squad`
  spawns one (the tests' and, from C2, the dev tools' and the campaign's).
- Lifted from the co-op soak bot into game code, with tests: `FollowBrain` (keeping station off a
  leader, boarding and leaving his vehicle, getting inside his extraction point), `ProgressWatch`
  (headway, detours a different side each time, "held up" at 30 s, "unable" at 90 s), `CareRules`
  (who's treated next, who carries, when to give up), `Extraction.missing_of` (any group), and
  `DeadGround.known_watchers` (plan from what our side knows, never the true positions).
- New suite: high_command.

#### Fixed
- Allied elements, US troops and allied garrisons were removed from the game when a player joined
  or left (the player squad's rebalance took every friendly AI without a slot for its own).
- Allied elements' men showed in the command menu's F-key roster.
- Another friendly squad counted the human players as its own men, and formed them into its slots.
- A hero squad's or element's shouts reached every player on the map (now within 50 m).
- An AAV's boarders and the contact callout used the player squad, not the speaker's own.
### Performance: the woods perf pass and F-121 (cghath's brief, queue item 1.8)

#### Changed
- **Dense copses in the normal zones.** Every wooded preset (temperate, river valley, highland moor, coastal lowland,
  amphibious coast, rocky ridge, scrubland, and the new snowy mountain and farmland) now has the Experimental forest's copses-as-cover layout: bigger, denser
  copses with a skirt of thickets and rocks inside, a thicket belt round the woods, and its higher caps. Temperate
  and river valley also get more woods (2.1 a km², was 1.5 and 1.8) and copses (6, was 5). On temperate's hot zone
  that's 9,000 trees (was 5,000) and 21,700 thickets (was 11,000): the dense layout's thicket cap is
  16,000 (was 11,000), so the last copses of a big zone still get their skirts. A fresh layout of that zone takes
  longer (4.2 s, was 1.8 s on this PC; 0.46 s from the disk cache after). Desert, badlands and salt flats keep their small
  copses.
- **Trees draw in two tiers.** Within 200 m of a cell's middle they're drawn as before; further out, low-poly
  versions in the same places (a crown 44 triangles instead of 164, a thicket 38 instead of 152), and past 950 m the
  canopy blobs. Each tree shows in exactly one of the three. The blobs come in blocks of 2 x 2 cells (a quarter of
  the draws). The full shapes lose the faces nobody sees (hidden caps between tiers, under the ground, inside the
  crown), so they look the same with fewer triangles.
- **Cheaper sight lines through the woods.** Foliage is indexed in 16 m squares, and a sight line only walks the
  squares it crosses, from both ends. The AI's lines stop once the target is hidden: the answer is the same as
  before (checked against the old walk), just cheaper.
- Measured headless, back to back on a PC shared with other agents' runs (R0498 before, R0499 after), from the densest
  copse of temperate's hot zone with the dense copses:
  - draws 590 -> 435;
  - triangles in view 1.70M -> 0.64M;
  - shadow-pass triangles ~231k -> ~159k;
  - a sight line 4.3 ms -> 0.39 ms;
  - a nav chunk's scatter 0.75 -> 0.06 ms;
  - building a cell's visuals 27 -> 6 ms.
  - With 16 AI fighting round the Experimental forest's densest copse, their sight lines through the leaves cost 9.0 ->
    0.38 ms a frame. Frames averaged 41 -> 31 ms (p95 199 -> 94) on that shared PC.
  - Standing in the copse alone: 6.9 ms a frame both before and after (the headless frame has no drawing).
  - A scan round of 16 men's sight lines through that copse (128 lines): 649 -> 11 ms (R0519 / R0517).
  - Temperate's hot zone as its preset now says (dense) against as it was (R0517 / R0519), from its densest
    spot: 627k triangles in view (was 566k with half the woods), 610 draws (was 273; this spot is by a
    settlement, its props and wires a third of them), ~152k shadow triangles (was ~39k).

#### Fixed
- **The vehicle range's concrete blocks and sandbag wall are there (F-121).** They lay outside the range's 22 m voxel
  area, so they were never built: no voxels, no collision. A level's voxel area now grows to hold its structures.
  The AI driver has something to steer round, and a demo block on a concrete block carves it.
- **The insertion helicopter keeps 7 m over what stands in its way (was 6),** the same margin it keeps over the
  ground. With the dense copses moving its line, harbour yard's flight in came over a roadside billboard 4.99 m clear
  while banking (the check asks for 5).

#### Tests
- `forest` checks, with Proposed budgets:
  - a normal preset's dense copses: laid out the same twice, and drawn within a budget of draws and triangles;
  - each cell's trees drawn exactly once, near and far;
  - sight lines the same as the old walk, and within a time budget;
  - nav geometry the same and cheap;
  - the frame standing in the forest's densest copse, and a 16-man scan round through it.
- `demolitions` checks the range's blocks and wall are built, stop rays, and carve under a demo block.
- `world`: temperate now has the dense copses.
- `vehicles`: its AI driving goals moved clear of the range's blocks (they're there now); an AI vehicle turning
  round beside one is F-223.

### Prop library (cghath's brief, queue item 1.7: "at least triple today's outdoor set")

#### Added
- **72 new outdoor props**, on top of the 25 shapes the open terrain and the sites had (rocks,
  scrub, trees, crates, drums, debris, ruins, box wrecks, sandbags, HESCO, towers, tents and the
  rest): 97 in all.
  - Street furniture: street lamps (single and double), wooden utility poles (some with a
    transformer), stop, warning and direction signs, a billboard, a bus shelter, benches, bollards,
    skips, a kiosk, concrete road barriers.
  - Market: stalls with striped awnings and produce, big canopies, shop awnings, produce crates,
    hand carts.
  - Fences and gates: post-and-rail, board, chain-link, barbed wire, corrugated iron, dry stone,
    block and mud-brick walls; farm, steel and wooden gates (open).
  - Power lines: steel lattice pylons and H-frame wooden poles, with sagging wires from each to
    the next.
  - Farm and water: wells, raised water tanks, cisterns, troughs, round and square hay bales,
    irrigation channels with sluices and pipes, windpumps, animal shelters.
  - Animals: goats, sheep and dogs. They wander about their pens, farms and streets (nothing more),
    the same on every peer; a round kills one.
  - Scenery vehicles built from blocks the shape of the real thing: saloon and hatchback cars, a
    panel van, a pickup, a dropside lorry with a canvas tilt, a tanker, a tractor, and burnt-out
    hulks of a car, a van and a lorry. They're scenery, not drivable.
  - Shipping containers: 20 ft, 40 ft and a stack of two.
  - Graves: mounds, headstones, crosses, box tombs and the arid style's stone-bordered graves.
  - Site clutter: generators, satellite dishes, washing lines, fuel tanks, gas cylinders, pallet
    stacks, tyre piles, portable latrines.
- **Where they go**, by the zone's terrain style (`data/props.json`: temperate, woodland,
  highland, coastal, arid) and what's there:
  - Towns: lamps, and poles with wires, along the streets; market stalls by the crossroads;
    parked cars, benches, skips, a kiosk, bollards, stop and direction signs and a bus shelter.
    All of it stands on the street, clear of the buildings, barricades, guard posts, loot and the
    civilians' walks.
  - Villages and towns get washing lines, dishes, a well or a water tank, a small pen and dogs
    round them.
  - Sites: containers, generators, fuel tanks, latrines, barriers and a chain-link yard outside
    the HQ, QRF bases, outposts and compounds. Checkpoints get barriers in a chicane and stop and
    warning signs on the way in.
  - Roads: utility poles along most of them, direction signs where they reach a site, a bus
    shelter and a billboard on the way into a town, and parked or abandoned vehicles (some burnt
    out, now and then a cluster where an ambush was).
  - Countryside: pylon lines across the zone; farms with a pen of goats or sheep, water, hay, a
    tractor, field fences with gates and sometimes an irrigation channel; a walled cemetery by the
    biggest settlement.
  - The campaign's zones had 390 props between them; they now have about 11,900.
- **New suite `props`** (two processes, like world): the library and every campaign zone's layout,
  collision against what's drawn, rounds through props by material, AI cover behind a container,
  animals wandering and the same on a late joiner.

#### Changed
- **Every prop's collision is what's drawn**, part by part, and each part takes rounds by its
  material. An M855 goes through a car's cabin, a shipping container's width, wooden fences and
  chain-link; a 9 mm stops in the car or the container. A car's engine bay, concrete, stone, a
  generator, a hay bale, a full tank and a mud wall stop rifle rounds. The AI's soft-cover test
  agrees, so it hides behind an engine block or down a container's length, not behind a door.
- Chain-link and barbed wire stop men walking, but not sight or rounds.
- The old box car wrecks out in the open are burnt-out hulks now.
- Rocks, trees and bushes keep off the props.
- Scatter props no longer count as foliage that hides people. They were treated like bushes on
  top of being solid.
- Props keep out of rivers, lakes, their wet banks and bridges (as the rest of the scatter does);
  a power line spans a river, one footing skipped. Landmark sites (a mosque, a farm, a harbour
  and the rest) keep the props they build themselves: the library adds none on their pads, and
  its farms keep their distance from a landmark farm.
- Zone layouts cache under a new version (13), so old caches re-roll.
- Helicopters climb over pylons and other tall props near their track. A pylon's lattice was too
  thin for them to sense, and an insertion flew into one.

### Terrain features and presets: gullies, cliffs, marsh, snow and farmland (cghath's brief, queue item 1.3)

#### Added
- **Gullies and ditches that give cover.** Dry gullies (2-3 m deep, a flat floor and steep
  sides) and shallower ditches wander across the temperate hills, scrub, desert wadi, moors,
  badlands, ridges, river valleys and coast. Lie down in one and you're out of sight of the flat
  around it; crouch in a gully and you mostly are. The AI sees them the same way: it can't spot
  a man down in one, and its cover search sends a man to one when he's caught in the open
  (prone at the lip, firing over it, or down in it).
- **Cliffs and rock faces.** Escarpments 6-18 m high on the ridges, moors, badlands and the new
  snowy mountains: a sheer rock face with a ledge on top and the ground easing back down behind
  it, fallen rock at its foot, tapering out at both ends so the way round is short. Nobody walks
  or drives up the face and the AI's paths go round it. Roads that cross one climb it on a ramp.
- **Marsh.** A new fen preset: soft ground in patches that slows you to about two thirds of your
  pace, reed beds that hide a crouched man, dark wet mud, dozens of shallow ponds and pools, a
  sluggish stream and drainage ditches. Blackwater Fen (inland) is one.
- **Snowy mountains.** A new preset: big hills under snow, a snow line that climbs in summer and
  comes down to cover everything in winter, bare rock on the steep faces, cliffs and gullies,
  tyre tracks in the snow and a cold, hazy sky. Deep snow slows you to about three quarters of
  your pace, but not on the roads or cleared ground. Its streams and ponds are frozen: ice you
  walk on. Whitecap Pass (inland) is one.
- **Farmland.** A new preset: a patchwork of fields round the farms (never over a farm's yard
  or any site) with wheat, maize, vegetables and fallow ground that change with the season
  (green in spring, ripe gold and tall maize in summer, stubble in autumn, bare in winter),
  orchards in rows that blossom in spring, hedges along some field edges, and irrigation
  channels you wade through. Ripe wheat hides a man lying in it; maize hides a man standing.
  Harrow Fields (inland) is one.
- **Seasons.** The campaign now has a season, from the campaign day: 30 days each, starting in
  spring. Zones you go to are built for the season you go in.
- **Mixed terrain.** A "procedural" zone can now mix in the marsh, snow and farmland presets, and
  takes their features (a snowy ridge with gullies, farmland in a marsh).
- A `terrain` test suite, and `tests/terrain_shots.tscn` for headless pictures of each preset.

#### Changed
- The rocky ridge, highland moor and badlands presets have cliffs, and most presets have gullies
  or ditches, so those zones' ground is new.
- **Farms and fields agree.** On farmland the farmsteads stand on the rough ground by the fields,
  their fences and gates run down the lanes between the fields, and nothing stands in a crop
  field but the power lines' pylons and poles. Fields keep clear of the roads' verges. Marsh
  zones take the woodland props, snowy mountains the highland ones.
- **Cities get their street furniture once.** A city's lamps, benches and bins line the pavements
  of its whole street grid, laid in one pass instead of a town's street kit inside every block;
  building a city zone's props takes about a tenth of the time it did.
- **Flatter helicopter LZs.** A helicopter insertion or wave-off now looks a little further for
  a hidden LZ of 8 degrees or less before settling for a steeper one, so on the mountains it
  lands instead of hovering on a slope it can't sit on.

### City zones and village houses (cghath's brief, queue items 1.5 and 1.6)

#### Added
- **Cities.** A city is a street grid of blocks: 5 x 4 blocks, 10 m streets between and round
  them. Each block is a ring of terraced buildings along its four streets, fronts on the street,
  narrow alleys between them and a courtyard behind. The inner blocks are 3-5 storeys, the outer
  ring 2-3, and two or three 6-8 storey towers stand out over the core. New building types: an
  apartment block (flats on every floor), a tenement (a shop under flats) and a tower (offices).
  Some buildings are ruined, and there are barricades and rubble in the streets.
- **Stairs to every floor and the roof.** Every building over one storey has a flight up from
  each floor to the next and onto its roof, and the AI's navigation covers every floor and roof.
- **Garrisons hold the upper floors.** A city's defenders stand at upstairs windows onto the
  street, in back rooms upstairs and on the roofs, and the towers are held from the top floor
  and the roof.
- **The Old Quarter is a real city.** Its towns are replaced by a city near the enemy HQ, with a
  road in from the HQ and a patrol round its inner streets, on a new "city" terrain preset (low
  ground, dusty verges, grey streets, few trees). Each block streams in on its own, so the city
  loads round you as you walk in, and each block is a town to missions (raids, HVTs, hostages,
  intel), the townsfolk and the enemy's defence.
- **The street grid is data the roads can use** (the zone's "cities"): paving it is F-210.
- **A `city` test suite**: the city by seed, its storeys, stairs, rooms and garrison posts, the
  Old Quarter, the village, and in the world the navmesh up a tall building, the AI's building
  scan from upstairs, the garrison upstairs and a city block's frame time as it streams in.
  Pictures: `tests/city_shots.tscn`.

#### Changed
- **Village houses are generated.** The village's four houses (mud brick, cinder block, a
  two-room brick house and a plank shack) are now generated buildings with rooms, furniture,
  windows and their own look, each where the old one stood with its door in the same place. The
  village's layout, garrison posts, loot and mission spots are as they were.
- The AI's navigation in zones now reaches the top of tall buildings (it stopped 8 m up).
- More physics bodies are allowed (Jolt's limit is 32 768), so a whole city can be loaded.

#### Fixed
- Stairs in city buildings always join the floor on the AI's navigation (a short space in front
  of the first step could cut a stair off, depending on the ground's height). Every stair's
  navigation ramp now has a wedge on and off. Towns and landmarks keep their stairs as they are
  for now (F-212).

#### Known
- An AI order from the street to a tall tower's top floors first paths a floor or two short and
  re-paths on the way up (Godot's path search stops at 4096 navmesh polygons: F-213). A city
  block's AI building scans can take 150-450 ms near tall buildings (F-211).

### US forces in the living war (combined arms, phase D7)

#### Added
- **The US is at war.** US forces now hold ground in the living war, as the factions do. They
  fight the Ashen Banner first. Once the company wipes the Banner out, they turn on the Kestrel
  Cartel. If Kestrel goes too, their war ends and they keep what they hold. They start at
  strength 70 and gain a flat 3 a day. From day 3 they open one front of their own at a time on
  Banner ground beside theirs. Where none is beside them, they push through the zone in the way.
  The Banner, and anyone else at war with the US, can attack US ground.
- **FOB Halberd.** It's a new US base on the coast, north of Cove outpost, held from day 1. It
  can be besieged but never falls. No contracts are offered inside it, and every site there has
  an American garrison. It's green on the theatre map, under the US flag.
- **Joint operations.** A US front posts an operation on the US board once, if the company is
  Trusted with the US. Vessmark posts one beside it. While the operation is on the board or under
  way, that front waits. Complete it and the zone goes to the US. Fail it and the US loses
  strength. If nobody takes it, it expires after 4 days and the front fights on without the
  company. Until the full operation contracts (D3) arrive, an operation is a one-phase raid,
  sabotage or HVT job against the zone's holder.
- **The Vessmark Defence Ministry.** This new fictional government employer belongs to the
  coalition, allied with the US, the UK and Canada. It wears its own grey-green camo, carries
  Canadian weapons and flies a slate-blue flag. Its work only comes beside US operations, and it
  pays 10% more.
- **US forces in the field.** In zones the US holds or borders, a US patrol drives the roads
  from site to site in an M-ATV and a MaxxPro with a rifle squad aboard, and gets out to fight
  when hit. A US-held zone has a US garrison at its HQ site, while the Banner's last men hold its
  other sites. US convoys come in along the MSR from neighbouring US ground. A section of two
  Bradleys moves up to overwatch a US front, with an Abrams leading once the US is strong. Every
  US group is green, uses callsigns (Saber, Anvil, Iron, Citadel) and talks on the US net.
- **War news and radio.** The morning news covers US offensives, gains, sieges and operations,
  and the US turning on Kestrel. Where US troops are about, enemy nets talk about them.

#### Changed
- Fronts opened by the US don't count toward the factions' limit of 3 open fronts.
- A zone the US takes isn't a flashpoint, so no job against the US goes up there.
### Combined arms A1: the armour model (docs/combined_arms.md 2.3-2.4)

**For phase A2 (handover):** `ArmourModel.damage()` (scripts/combat/armour_model.gd) is A1's
bridge onto the old zones: replace it with the module path, and keep `vehicle_hit()` and the
pure `resolve()` (its HitResult has the outcome, `pen`, `t_eff`, `residual`, `burst` and
`tiles_fired`). Fired tiles and fitted packages live in vehicle metadata (`armour_tiles`,
`armour_packages`) until A2/A7 put them in `net_state`. Charges, mines and fire support (HE with
no warhead id) and rifle rounds still use `VehicleDamage` on plated models (calls 79 and 80).
New per-model data goes in data/vehicle_modules.json; `VehicleSpecs.spec` already merges it.
docs/combined_arms.md calls 74-92 list A1's decisions.

#### Added
- **Armour that cares about angle and where you hit.** The Abrams, Bradley, AAV, M-ATV and
  MaxxPro now have armour plates: turret cheeks, mantlet, glacis, skirts, sides, roofs,
  hatches, bellies, windows and tyres, each with its own thickness against sabots and against
  shaped charges. A round's angle to the plate matters. Sabots and APDS turn slightly into the
  plate, and steep hits can bounce off. A big enough round overmatches a thin plate and goes
  through at any angle. RPGs and other shaped charges can glance off as duds at very steep
  angles. The Abrams front shrugs off what kills it from the side, rear or roof, and an RPG
  still kills an AAV from the side.
- **Reactive armour and slat.** Tiles are used up when they fire, so the next round through the
  same spot meets bare armour. The Bradley wears BRAT I tiles. Light tiles stop single RPGs but
  not tandem ones, tandem-capable tiles stop both, and heavy tiles also blunt sabots. Slat cages
  short out about half the RPGs that hit them and weaken the rest. Upgrade packages are in the
  data, ready for the motor pool: TUSK I and II, BUSK III, and slat kits for the AAV and MRAPs.
- **Fuzes.** Rounds now have point-detonating, delay, shaped-charge, tandem, proximity and
  airburst fuzes, plus arming distances and self-destruct. HE can blow in thin plates such as
  MRAP roofs and technical skins, but not a tank's.
- **The tank and IFV rounds and the missiles.** These are in data now: M829A3, M830A1, AMP,
  25 mm, 30 mm and 125 mm rounds, the .50, 12.7 mm, 14.5 mm and 23 mm API, plus PG-7VL,
  PG-7VR, TBG-7V, PG-9, M344, Type 63, TOW-2A, Konkurs-M, Kornet and 9M119M. Guns and
  launchers that fire the new ones come in later phases.
- **The armour suite (armour_test).** It checks angles, normalisation, overmatch, ricochet,
  graze, tiles, slat odds, HE, fuzes and plate lookup. It also checks the design doc's "who
  beats what" table cell by cell against the data, and that a hit resolves in under 0.05 ms.

#### Changed
- **The .50 against MRAPs.** A .50 now goes through an M-ATV or MaxxPro side only up close (inside
  about 100 m), not at any range. It still wrecks wheels and engine bays.
- Rifle rounds, demolition charges, mines and fire support hit vehicles exactly as before, and
  so does everything that hits a technical, a helicopter or a static gun.
### AI follow-ups: road ambushes, halls, dug ground, smoke and bangs, flares, patrol formations

#### Added
- **Road ambushes that wait for the convoy (F-140).** Enemy teams laid by a road hold their own
  spots in cover, down and facing the road, holding their fire. They spring it as the first truck
  comes level with them, every man opening up at once: the gunner on the mounted gun first, then
  the crews, the rocket men at the lead truck and then the last one. They spring early if they're
  given away (fired on, a man down, or found up close). They fight from their ground rather than
  chase the convoy or charge the hill, and run if they're beaten.
- **Convoy trucks drive through an ambush.** A truck driven as a convoy's pushes through the kill
  zone faster, its gunner firing as it goes. If it's knocked out, its crew bail out on the side
  away from the fire and hold there.
- **Smoke and bangs (AI bar G-14).** Under fire, the AI throws smoke before crossing open ground
  the enemy can see (a bound, falling back, a move order) and before dragging a casualty off in the
  open, once a squad on the same ground. Clearing a building known to hold the enemy (or close to
  a fight), a stack with no breacher bangs the room before going in, and the stack bangs up the
  stairs before each push upstairs, the thrower at the foot of the stairs. Our side uses a
  flashbang first, the enemy a frag. Never with a civilian or an HVT inside.
- **Enemy flares at night (AI bar G-24).** When an enemy hears contact or takes fire in the dark,
  his squad puts up illumination over it: a hand-fired parachute flare (one enemy in four carries
  two), or a mortar illumination round where his side has a mortar team set up in range. A hand
  flare bursts about 150 m up and lights the ground for about 35 s; a mortar's burns higher and
  longer over a wider area. The lit ground is seen almost as by day by both sides, and NVGs bloom
  in the light and when looking at a flare. Hand flares are loot.
- **Patrol formations (AI bar G-26).** Enemy patrols walk their routes in formation behind their
  lead instead of in a bunch. The formation follows the ground and the threat for both sides: a
  file in the woods, a staggered column on a road when on the alert or at night (a column when
  it's calm), a wedge on open ground (a staggered column at night), a staggered column in town, a
  line in contact. Each doctrine has its own spacing: insurgent bands bunch up, regular armies keep
  the drill's gaps.

#### Changed
- **The AI shoots at moving vehicles.** Against someone riding in a vehicle it aims at the vehicle
  and leads it by its speed. Before, a truck driving past at speed never let it settle its aim,
  so it never fired.
- **Vehicle gunners take time to spot you.** The AI on a mounted gun has to make someone out
  before it fires, like any soldier (range, stance, cover, camo, the dark). Before, it saw anyone
  in a clear line at once, out to 600 m.

#### Fixed
- **Foxholes, trenches, berms and craters come back when a zone loads from its save (F-176).**
  They were saved but dropped on loading.
- **Hangars and factory floors count as buildings (F-162).** The AI's building scan missed the
  middle of a big open hall, so it never garrisoned or cleared one room by room.
### Performance pass (Captain, 2026-10-22: "we definitely need more performance fixes")

#### Changed
- **Smoother towns, fights, woods and flights.** Measured on five scenes (the Old Quarter, a Black
  Ridge fight with the QRF coming, Kestrel Valley's woods, an M-ATV and a UH-60 crossing it), the
  game's own work per frame came down by a quarter to more than half: the Old Quarter from 51 to 21 ms
  a frame (its worst frames 307 to 67 ms), the helicopter flight from 18 to 10 ms with its 310
  stutters a minute gone. docs/performance.md has the numbers and how they're measured.
- **Far-off enemies think less often.** An enemy more than 120 m from every player who isn't in a
  fight looks round, thinks and re-plans his route less often the further away he is. Anyone near
  you, shooting, being shot at or tending a casualty runs at the full rate.
- **Soldiers standing still cost less.** A garrison man at his post, doing nothing, works out his
  footing a few times a second instead of every tick.

#### Fixed
- **Stutters when soldiers appear.** A soldier's spawn went from about 45 ms to under 10 (a head's
  size no longer builds the whole face; armour shares its meshes), and the uniforms a zone will use
  are built in the background as it starts, so the first soldier in each uniform, and his first
  reload, no longer hitch.
- **Stutters in towns.** A squad's look round the buildings near it is spread over frames instead
  of taking up to half a second in one.
- **Stutters walking, driving and flying.** The grass round you, the woods' cells and the ground's
  near detail are laid a little at a time instead of in bursts.
- **Stutters in firefights.** Bullet marks on walls are added one at a time instead of redrawing
  all of them for each new one; blasts take out their voxels in one go; craters redraw their ground
  over a few frames; tracers and impacts reuse their meshes and materials, and their shaders are
  ready before the first shot.

#### Added
- **World detail at distance** (Settings, Video). Ultra draws everything as before, the tree
  canopy to the horizon; High (the default) stops the canopy at about 3 km, fading out, and soldiers
  further than 150 m cast no shadow; Medium and Low draw woods, rocks and scrub less far out and
  drop soldiers' shadows nearer. Up close they all look the same. The woods change in the next zone.
- **Performance cases** (suite perfcases, in CI) with frame-time and stutter budgets, so a change
  that slows these scenes down shows up.
### Requests to friendly units: the plumbing (combined arms phase B4, part 1, docs/combined_arms.md 4.1-4.3, 4.6)

#### Added
- **Requests and their answers.** A request to a friendly unit (suppression, a medic, CASEVAC,
  smoke, armour, hold, cover, a pick-up, ammo, a sitrep) goes to the nearest group that can do it
  and hears you. After a radio delay it answers yes with an ETA, no with a reason ("We're pinned",
  "Ammo black", "No medic free", "Out of range"), or offers a later time you can take or cancel.
  Three can be open at once, and asking the same thing twice merges. A sitrep is answered at once
  from what the side knows. The units don't carry out the jobs yet (phase B2), and the menus that
  send requests come with the contextual menus (C6).
- **Request cards** under the objectives show each request: who answers, what, its state and
  the ETA counting down, with accept and cancel.
- **Allies ask you.** An allied group in contact and in trouble, or out of ammo, calls the nearest
  player on the net ("Any station, Saber 2, contact, need support at 041 053"). A card shows
  where it is and asks yes or no. Helping counts toward your cooperation.
- **Radio voice.** Net lines are put together from recorded words, digit by digit. The clips are
  still to be rendered (tools/voices/gen_radio.py needs Piper); until then the lines show as
  subtitles.
- New test suite requests, in tools/run_tests.sh and CI.

### The side picture: what each side knows (combined arms phase B1, docs/combined_arms.md 3.2, 3.3, 4.4)

> **Status (2026-10-22 ~01:10 CDT):** side_command, requests and smoke pass locally; missions
> (R2402) fails only its zone-generation check, which runs before any B1 code (the landmarks
> red claude/ci-cleanup fixes). Remove this note when B1 lands.

#### Added
- **Spot reports on the map.** What your side has reported shows on the map as it was reported:
  a symbol by what was seen (men, an MG, an AT team, a sniper, a vehicle, armour, a mortar), how
  many and how long ago, inside a circle for how sure anyone is of where they are now. Fresh
  reports are solid, older ones dashed, and past three minutes only a "last seen" circle is left.
  Hover one to see who sent it and when. Nobody sees anything that wasn't reported.
- **Spot reports in the world.** A small diamond hangs over each reported enemy within 800 m that
  you can't see yourself. Your side's tags are red, everyone else's reports amber, and they fade
  as they age. Settings > HUD turns them off or changes the range.
- **Reports take radio time.** A squad's sighting reaches the side over the radio after a delay:
  3-8 s for the company and allied regulars by their leader's skill, 8-20 s for Eastern Concord,
  15-45 s for the cartels and Black Ridge, and the insurgents as before. With the net down it's
  three times as long. A group whose radio man is down holds what it saw until it meets someone
  with a radio.
- **Your own forces are tracked.** Friendly vehicles with a working radio are tracked where they
  are, and go grey if the radio is knocked out. Groups are tracked by their sitreps every 30 s.
- **The group board.** Every group on each side is listed with its strength, anti-armour power,
  combat effectiveness (green, amber, red) and ammunition. The AI commander (phase B2) will task
  groups from it.
- New test suite side_command (merging, ageing, latency by side, comms down, tracking, fairness,
  the budget), in tools/run_tests.sh and CI.

#### Changed
- The hot-zone enemy commander now keeps its picture in the same form the friendly side uses.
  Its decisions read the same reports as before, so hot zones play the same.
### Missions 2: HVT kill, crash site, overwatch, night and weather contracts (Captain's list, 2026-10-20, "Not built yet / Campaign")

Closes the list items "mission types: HVT kill with proof, crash site / black box, overwatch" and
"contracts that roll night and bad weather". All numbers are Proposed (docs/missions.md "Missions 2").

#### Added
- **HVT kill.** A named commander at a compound, village, town, outpost or HQ, with a guard
  detail of 2-4 who keep with him as he walks between the site's buildings. Kill him and carry
  his ID papers (taken off the body) out at extraction. Without the papers the client holds back
  40% of the pay; taken alive and brought out counts in full. 90 minute clock; bonus for his phone.
- **Crash site.** A downed Viper, Black Hawk or Petrel lies as a wreck in open ground. Carry its
  flight recorder out (14 kg, both hands). Bonuses: the crew's ID tags, and denying the wreck with
  a breaching charge. Enemy waves converge on the site, each sooner than the last.
- **Overwatch.** A friendly convoy of one or two armoured trucks drives past an enemy site, with
  ambush teams by the road. The squad takes the high ground over the route (the position moves
  to the highest ground nearby); the convoy sets out once someone holds the position, or after
  10 minutes at the latest. Done when it is through, failed if it is lost. Bonuses: every truck
  through, and staying on the position until it is through. The convoy's crews are the client's:
  they are not squadmates and don't count as casualties in the debrief.
- **Night and weather contracts.** A contract sometimes rolls a night start (21:30-03:30) or bad
  weather. Night is likelier on recon, sabotage, raids and kills, and rarer on escorts, holds and
  overwatch. Weather depends on the zone's terrain: fog on coasts and moors, little on the salt
  flats, storms rare everywhere. The board shows it ("NIGHT FOG" on the line) and the brief says
  "Conditions: Night (insertion about 23:15), fog: +15% pay". It pays more: night +10%, fog or
  rain +5%, a storm +10%. The deployed zone starts at that hour and weather, even when the zone's
  save remembers another. The safe job and in-zone radio contracts never roll it.
### Voxel smoke (Captain's list for cghath, 2026-10-20, "World": S5, "Voxel smoke (CS2-style)")

#### Changed
- **Smoke is a volume now, not a ball of puffs.** A smoke grenade's cloud fills a grid of
  half-metre cells. It spreads from the grenade cell by cell and stops at walls, floors and
  ceilings. A closed room fills and holds it; from a room with a door, what doesn't fit pours out
  of the doorway. In the open it builds a low, rounded cloud with a ragged edge. It drifts with
  the wind (stronger in rain and storms), thinning on its upwind side first, then thins and is
  gone after 30 s as before. It looks like the game: see-through boxes for the thin outer layer,
  opaque boxes in the body, in the grenade's colour.
- **What the AI can see follows the real cloud.** Sight is blocked by how much smoke is actually
  on the line: half a metre of the cloud's body blocks it, its thin outer layer doesn't. Smoke in
  a room blocks a look in through the door only once it fills the doorway.
- **Blasts push holes in smoke.** A frag, rocket, mortar round, charge or car bomb clears the
  smoke round it; the hole fills back in from its edge over about two seconds. A wall it blows
  open lets the smoke through.
- **Rounds part smoke for a moment.** Shooting through a cloud clears the cells on the round's
  line, so you can see down it for about a second before it closes.
- **Every player sees the same cloud**, late joiners too. The host sends a cloud's seed and its
  blasts and rounds, and every machine grows the same one. Coloured smokes keep their colour, so
  purple still sets an extraction point and the helicopters still land on theirs.
- The M320's M714 smoke round and fire support's smoke shells make the same clouds, picked by the
  host like a grenade's.

#### Added
- A `smokecloud` test suite (also on CI): a room filling and stopping at its walls, smoke out of a
  door, the compound's shed, sight through thick and thin smoke and through a doorway, thinning,
  wind, a frag's hole refilling, rounds parting it, purple, the same cloud from the same seed (for a
  late joiner, and after an event that arrived late), and the cost of eight clouds at once.
### Docs brought up to date with the build (cghath, 2026-10-20)

#### Changed
- `docs/feature_comparison.md` 11.2: ALiVE-style virtualization is built, not only designed.
- `docs/contractor_design_doc.md`, player death: the default kit, the marker and the respawn pool
  are built (it still said the build respawns players at the gate with full gear).
- `docs/ui_audit.md`: the gamepad layout and pad wheel (wave 7) and the automatic UI scale are
  noted where the audit said there were none.

### Water: rivers, streams, lakes and bridges (cghath's brief, queue item 1.1)

#### Added
- **Rivers that cut their own valleys.** A river valley zone has a real river running edge to
  edge. It meanders round the sites and flows downhill all the way, deep enough in the middle
  that you swim. Its banks stand over the water and its valley blends back into the hills.
  Kestrel Valley has one.
- **Streams, lakes and ponds.** Streams spring from the hills and wind downhill into the river,
  a pond or off the map. There are farm ponds in the temperate hills, burns and a tarn on the
  moors, and stock ponds in the scrub. Reeds grow in the shallows, trees along the banks, and
  nothing grows in the water. The banks are dark wet mud and gravel.
- **Flowing water.** Ripples drift downstream at the current's speed in the same blocky voxel
  look as the ground. Deep water is darker, and there's a pale fringe at the bank.
- **Wading and swimming.** The deeper the water, the slower you go. Knee-deep is about two
  thirds of your pace and waist-deep under a third. Past 0.6 m you can't sprint and past 0.45 m
  you can't lie down. A current pushes you along. In water deeper than 1.45 m you swim with
  your head and shoulders out, slowly, and slower still under a heavy load. Your hands are
  busy, so no shooting, reloading or throwing, and the current carries you. You don't drown.
- **Bridges, fords and culverts.** Every road over a river has a bridge: concrete (spans on
  piers, parapets) or steel truss. No stretch of river goes 450 m without a way across: a
  timber footbridge or a ford, where the river shallows to knee-deep with gentle banks and depth
  posts. Where a road crosses a stream there's a culvert (an embankment over a pipe) or a ford.
  Bridges have real collision. Trucks drive over them and through fords, men walk them, rounds
  stop on them, and the AI's paths use them (deep water isn't on the AI's map).
- **Bridges can be dropped.** A big enough blast drops a span into the river. One demolition
  block drops a footbridge. A concrete span takes three, a steel truss span two. A truss span
  falls to about six 105 mm rounds. Grenades only chip. A dropped span lies in the river: an
  end span hangs from its abutment, a middle span lies on the riverbed. The AI's paths stop
  using it. Every player sees it, late joiners too, and it's saved with the zone.
- **Vehicles feel rivers and lakes.** They already handled the sea. A truck in water deeper
  than its fording depth floods and stalls.
- A `water` test suite.
### Landmark buildings (cghath's brief, queue item 1.4: world expansion)

#### Added
- **Landmark buildings**, each its own generated type with furnished rooms you can enter, fight
  through and blow holes in, and the AI can garrison and clear:
  - an **office** block: two storeys and a roof;
  - a **mosque**: a prayer hall under a dome, a minaret, an ablution room;
  - a **church**: a nave with pews and an altar, a bell tower over its door, a gable roof;
  - a **school**: classrooms with desks and boards, often two storeys, a playground;
  - a **garage** workshop: a car on its lift, a wide door;
  - a **fuel station**: a kiosk, a canopy over its pumps;
  - a **factory**: a factory floor with machines, offices, a chimney;
  - a **farm**: farmhouse, barn, silos, livestock pens;
  - a **harbour**: a quay and two piers out over the water, cranes, sheds, the harbourmaster's
    office, containers, a moored boat;
  - an **airfield**: a runway, an apron, two hangars (a light aircraft in one), a control tower,
    a windsock;
  - an **oil field**: pumpjacks, flowlines, tanks, a flare stack;
  - a **fuel depot**: storage tanks in a bund, a pipe rack, a loading gantry and tanker, a fence;
  - the terror groups' sites: the cartels' **drug lab** (blacked out, lab benches, cookers,
    chemical drums) and the Banner's and the Shura's **IED workshop** (wire, phones, shells,
    jugs, a car being rigged).
- **Ruined and bombed-out variants of every building**, the old types too: walls breached,
  roofs fallen in, rubble; bombed out, a corner collapsed and an upper storey's roof gone. Stairs
  and doorways stay usable.
- **They appear where the zones' asset tags say** (docs/terror_groups.md 7.3): a mosque where a
  zone has one, a harbour on the coast of harbour zones, oil fields, airfields with a fuel depot,
  farms in the fields, fuel stations on the routes, garages at crossings, offices where there's a
  headquarters, the drug lab or IED workshop of the group that holds the zone, and a few churches,
  schools and factories. Each has a road to it and a garrison; hot zones' are more often in ruins.
  (data/landmarks.json; all numbers Proposed.)

#### Fixed
- **Upper-floor doorways no longer open onto the stairwell.** Now and then a doorway upstairs
  stood over the stair's opening, so the room behind it could only be reached by falling down the
  stairs; it slides along its wall now (or another wall takes the doorway).
- **The building docs no longer claim an office** before there was one (docs/building_gen.md,
  docs/feature_comparison.md 8.2): there is one now.
- **Loop suite, helicopter extraction:** the player sets down what's in his hands before his
  rifle (a drop lets go of the hands first, so a carried-out hard case kept the rifle slung), and
  a dead hostile's intel isn't expected in the stash (intel goes to the debrief, never the stash).

### Roads (cg_brief queue item 1.2)

#### Added
- **Real roads.** Every zone's roads are planned on its ground when it loads, the same on every
  machine: they curve round hills and follow the valleys, and the ground is cut and filled to
  them, so they run smooth with banks either side.
  - **Asphalt** (7 m, a dashed centre line and edge lines) between the main sites: towns, the
    HQ, QRF bases, comms, checkpoints, the FOB.
  - **Dirt tracks** (4 m, two ruts and a grassy crown) to outposts, compounds and villages, and
    on the cross-country trails.
  - **Junctions** where roads cross or join, and **roundabouts** near towns and where four main
    roads meet.
  - **Towns:** kerbed pavements along both streets and a mini roundabout at the crossroads.
  - Every site is on the network now (in hot zones the comms site, QRF bases, checkpoints,
    villages and the town had no road).
- **Roads you can drive on.** Roads have collision that matches what's drawn; AI drivers take
  them (the squad's drivers already route by road, and now follow the curves). Asphalt and
  pavements sound hard underfoot, dirt tracks soft.
- **Roads across the zone's edges.** A road leaves by each crossing into a linked zone, and the
  zone on the other side has the same kind of road coming in at its crossing.
- The map draws the curved roads, dirt tracks thinner than asphalt.

#### Changed
- The trails' patrols walk their curved trails.
- A helicopter coming round its J-hook over rising ground climbs back up to its height instead
  of holding level under it (it came over a rise 4 m clear of the ground, F-218).
- Roadside props (poles, parked cars and wrecks, checkpoint barriers, signs, bus shelters,
  billboards) follow the curved roads and keep off them, each road its own width (F-219).
- **Roads run over the bridges.** The rivers' bridges, fords and culverts are placed where the
  new roads run (every site's road, the roads in from the zone's edges), and each road runs
  straight across its bridge's deck and down its ramps instead of dipping under it onto the
  riverbed (F-175). Where two roads would cross a river side by side, the second joins the first
  either side of its bridge.

#### Fixed
- A stream's bank running past a site no longer lifts the site's flat ground (a checkpoint's pad
  had a 2 m hump in it).

### A head shot leaves its wound (Captain, 2026-10-21: "first time headshots still dont cause a wound", "on a downed state enemy")

#### Fixed
- **The round that kills with a head shot is now on record.** A rifle round through the head is
  fatal, but the kill used to come with no wound, so the first round into a downed (or standing)
  man's head left nothing on him. Only later rounds, into the corpse, showed. Now the fatal round
  leaves its head wound (and the hole in the model), seen the same by every player.
### Forward observer: eyes on the area (Captain, 2026-10-21: "im in the area observing it but nothing")

#### Fixed
- **Observing a target area counts when you can see it.** Before, only one point counted: 2 m
  above the dead middle of the area. A compound's walls or a building round it hid that point from
  every position, however well you saw the place, so the "get eyes on" step never moved. Now any
  clear sight of the area counts, from within range for 10 seconds: its middle, any of the
  targets (the technicals, the mortar pit), or points round its edge.

### One 12-gauge system (Captain, 2026-10-21: "we have standard and hi brass and breaching rounds for the skeleton key")

#### Added
- **Three 12 gauge shells for every shotgun:**
  - **Standard 00 Buck**: nine pellets.
  - **Hi-Brass Magnum Buck**: twelve faster pellets, a slightly wider pattern and about a third
    more kick.
  - **Breaching Rounds.**
  Standard and hi-brass work in every 12 gauge: the Remington 870, the Mossberg 590A1, the
  M1014, the Saiga-12 and the Skeleton Key. Breaching rounds work only in the M1014 and the
  Skeleton Key. Every other shotgun refuses them: they don't load, and the game says why.
- **The Skeleton Key**: a short-barrelled pump 12 gauge that clamps under a rifle's rail, with a
  toothed standoff muzzle and a three-shell tube that comes full of breaching rounds. 4 switches
  the trigger to it, as with the M320. Fire shoots it, R loads it shell by shell. Priced at $1100
  in the base shop, and found with the rare western rifles as loot.
- **870 Extended Full Choke**: a choke tube for the Remington 870, its upgrade in place of breaching
  rounds. It narrows the pattern to under half its width, so it reaches much further. Mounted
  from the inventory like any attachment. $250 in the shop, and loot where the muzzle cans turn up.

#### Changed
- **Every 12 gauge fires through one path** (cghath's tube shotguns). Each shell fires as what it
  is: the gun's tube, a speed loader and a Saiga-12 magazine each keep the shells they hold, in
  order.
- **Speed loaders hold any shell.** R tops a tube up from one in a single push when the tube has
  room for two or more; shells the gun won't take stay in the loader. Loose shells fill speed
  loaders and Saiga magazines from the inventory (Load magazines). A Saiga magazine takes no
  breaching rounds.
- **The loose 12 gauge rounds are Standard buck now, and slugs are gone.** Slugs weren't in the
  spec, and nothing needed them. cghath's M870 is the Remington 870. Old saves' items turn into
  those.
- **The M320 and the Skeleton Key fit every railed assault rifle, carbine and battle rifle**,
  the AK-12 too while there's no GP-25. They no longer fit SMGs, shotguns or DMRs. The SVD, SVDS
  and M110 are tagged as DMRs.
- **The breacher** carries the Skeleton Key under a compact Mk18, with breaching and standard
  shells, in place of the Mossberg. The AI breacher's "shotgun on the door frame" is a breaching
  round out of the Key; out of contact he tops the Key up with breaching rounds.

#### Fixed
- **An AI soldier with a tube shotgun counted no spare ammo** (audit F-131). Loose shells and its
  speed loaders now count for reloading, the ammo-low checks and scavenging.
- **cghath's buckshot pellets were scored as full bullets by gunfire gore.** Every pellet from
  any 12 gauge now scores as a pellet, and a hi-brass pellet hits a little harder.
### The medical menu (H) reads like a medic (Captain, 2026-10-21: "injury descriptions in the medical helper (H) need to be improved too")

#### Changed
- **The casualty at a glance, under the title:**
  - conscious, conscious but dying, unconscious, or cardiac arrest with the time left;
  - how much blood is gone, in words, and "bleeding out in about 2 min" while it runs;
  - breathing and colour, the pulse, and pain, in words.

  With a pulse oximeter, the SpO2 and pulse are shown in numbers too.
- **Treat in this order:** every injury down the right, worst first, each with its severity in
  colour (minor, serious, critical, life-threatening). Click one to jump to its body part.
- **Each injury in plain words.** Where it is, plainly ("Left thigh, inner", "Chest, right
  side"), and what it is in medic language:
  - arterial bleed (spurting) and venous bleed (steady);
  - graze, gunshot or fragment wound, through-and-through;
  - open or closed fracture, traumatic amputation (blast or gunfire);
  - open chest wound, tension pneumothorax, blast lung, head injury, internal bleeding;
  - burns by how much of the body.
- **Done and next, for each injury:**
  - What's been done: tourniquet on and how long ago, packed, bandaged, splinted, chest seal on,
    clamped.
  - What to do next, in order ("Tourniquet high above the wound, then pack it, and bandage").
    Items you don't carry are greyed and say so.
- **Not tied to one wound, listed as well:** cardiac arrest, a blocked airway, blood loss that
  needs a line and fluids, cold, concussion, a racing or slow pulse, pain.

#### Added
- **Trace a hit's path through the body** (Captain: "show a traced wound path for a selected hit
  so users can get an understanding of the anatomy"). Click an injury in "Treat in this order"
  (or press T on its body part) and the right-hand column shows that part of the body from the
  front and the side:
  - the bones, arteries, veins and organs, with what the round crossed drawn bright;
  - the channel from where it went in to where it came out (a ring) or stopped (an X).

  Below the views, the path in words, in the order the round met things:
  - "In: Left thigh, front";
  - "8 cm: left femoral artery, cut";
  - "9 cm: left femur (thigh bone), cracked by the shock wave";
  - "Out: Left thigh, back, a 19 cm channel", or "Stopped inside after 11 cm: still in him".

  T moves to the part's next hit; T or Esc goes back to the signs and the log. A round that
  stayed in can be traced too: where its channel ended is now kept with the wound and sent to
  every player.
### Tracers follow the round's real path (Captain, 2026-10-21: "tracers flight paths and ballistic arcs ... theyre still wonky depending on terrain")

#### Fixed
- **Tracers fly the round's arc.** A tracer used to be a straight line from the muzzle to the
  impact while the round flew a zeroed, dropping arc. At 800 m the line ran up to 2.8 m off the
  real path. Now every peer rebuilds the steps the host's round flew from the muzzle, its launch
  velocity and its round (`Ballistics.flight_path`). The streak runs along them and ends exactly
  at the impact, on flat ground, slopes, hillsides and voxels, at any range.
- **Clients draw the host's path.** The tracer message now carries the launch velocity and the
  round, so the client's streak is the host's path point for point. A shooter that the client
  draws a moment behind (smoothing) gets the streak started at the gun it sees, and the streak
  joins the real path within 12 m.
- **A muzzle in the ground no longer fires from the eye.** A muzzle pushed into a rise (prone
  on a slope) or a wall now fires from 3 cm short of it. Before, the round and its tracer started
  at the shooter's face.

#### Added
- **Mortar and artillery shells can be seen in flight** (Captain, 2026-10-21: "i wanna see the
  mortar streak down or up depending on weather conditions etc"). Every peer sees a dark shell
  with a pale streak fly the real arc in its real time of flight. A mortar team's shell goes up
  off the tube and over. A called mission's 81 mm or 105 mm round comes down out of the sky from
  the guns off the map. Both end exactly on the burst. The streak stays about a pixel and a half
  wide at any range, and fog hides it.
- **Wind by weather.** Each weather has a wind (proposed: fog 1 m/s, clear 3, overcast 5, rain 7,
  storm 14) from a direction each zone keeps (`DayNight.wind`). The wind pushes shells, so the
  arc leans and bends in flight: about 5 m at the top of a 25 s flight on a clear day, 22 m in a
  storm. The crews lay for the wind, so rounds still land where they did before.
- Mounted vehicle guns show tracers too (every fifth round red or green, the rest as faint ball
  streaks), along the same real path.
- A `ballistics` test suite: rounds onto a hilly terrain at 50, 300 and 800 m, up, down and across
  slopes, up a hillside 700 m out, and into voxels. Each checks that the impact is on the height
  field, the path goes through no hill, the rebuilt path matches the one flown, and the tracer
  follows it to the impact. It also covers a player's real shot from the muzzle, a muzzle in the
  ground, and the smoothed-shooter lead. The net suite checks the client's tracer against the
  host's path over ENet.

### Arms and hands take hits (Captain, 2026-10-21: "fingers and arms cant be hit it seems")

#### Fixed
- **Arms and hands can be shot.** The arms' hitboxes now follow the arms as they're drawn: on
  the rifle's grip and handguard, in a reload, carrying, or ragdolled. Before, they hung at the
  sides in the rest pose whatever the arms did. A round at a raised arm met no arm, and one
  where the arm would have hung wounded an arm that wasn't there. This was the same for every
  player, since hits are worked out on the host.
- The forearm's hitbox now takes in the whole hand, and the hit shape inside it is the hand as
  drawn (gripping, on the handguard, holding a magazine), not a relaxed one. A hand hit counts
  on its forearm.
- The part a round meets first takes the hit. An arm held across the chest is no longer
  swallowed by the chest's hitbox behind it. A woman's arm hitboxes sit on her own, narrower
  shoulders.
### Feet (Captain, 2026-10-21: "better feet")

#### Added
- **Real footwear at 0.5 cm.** Combat boots have a lugged sole with a heel, a toe box with a toe
  cap, laces with eyelets up the instep, a laced shaft with speed hooks, a padded ankle cuff and
  a pull loop. Trousers are bloused over the top. There are also sneakers (a thick light sole,
  white laces), leather shoes, sandals with straps over bare toes, and bare feet with five toes.
  Women's feet are smaller.
- **Footwear by kit.** Contractors and the armies wear boots: coyote for multicam, tan and desert;
  black for woodland and Vantage. Banner fighters and Saltline wear sneakers, and the Shura wear
  sandals. Plain clothes get sneakers, shoes or sandals, or boots with the field commander's
  shoes. A plain-clothes scheme can name its footwear in a sixth field
  (`civ:<shirt>:<trousers>:<skin>:<shoes>:<style>`).
- **Feet move like feet.** Each foot is its own part on an ankle joint, pitched to the ground
  each frame. It's flat when planted. Walking and running, the heel strikes with the toes up,
  then the heel lifts and the foot rolls off its bent toes. Kneeling, the back foot is up on
  tucked toes; prone, the toes dig into the ground. Down or dead, the feet go slack.

#### Changed
- Each leg's shin is drawn for its footwear (a boot's shaft, a trouser hem, a bare ankle), with
  the foot on its own node. That adds two meshes (about 1,000 to 3,000 triangles each) and two
  draw calls per body. A severed shin takes its foot with it. The leg's hit shape is unchanged.
- Posed parts (`forearm:grip:`, `shin:boots`) now widen with a heavier build, as the plain parts did.
### Helmets fit the new heads (Captain, 2026-10-21)

#### Fixed
- **Helmets are no longer too big.** They were shaped round the old, broader head and stood 3-4 cm
  off the new faces' heads. Every helmet now rides snug, with about 1.5-2.5 cm of padding all
  round, at every height and build, men and women. The LX-3's face guard closes round the face
  as before. Hits on a helmet land on the shell as drawn.
- Long hair on top no longer pokes through a helmet's crown.
- A woman's bun, braid or ponytail goes flat under a heavy helmet's ear covers or the LX-3's nape
  guard instead of showing through them, and comes back when the helmet is off.
- **A head that comes off takes its face with it.** The eyes, mouth and brows stayed hanging
  where the head had been while it rolled away, and a whole head could reappear on the stump
  (on clients, or once the helmet fell off). Now the flying head is the soldier's own, eyes shut
  and jaw slack, the helmet falls loose, and the body keeps only the torn neck. The same on
  every peer, alive or dead.
### Gunfire takes limbs (Captain, 2026-10-21)

#### Fixed
- **Shooting a limb enough takes it off, alive or dead.** The Captain shot a man over 40 times with
  the M1014, more than 20 rounds per leg, and the legs stayed on. Now every hit scores on the
  limb it hits, by how hard it hits, and past a limit the limb comes off:
  - Hands and feet go first (hits low on a forearm or shin take it at the wrist or ankle), then
    forearms and shins, then upper arms and thighs.
  - Close buckshot takes a shin in 2 or 3 shells and a thigh in about 5.
  - Heavy rounds take a forearm or shin in one or two hits: .338, and a .50 (which still kills
    outright).
  - 7.62x54R takes about 4 hits up close for a forearm or shin, at the Captain's call. So do the
    rounds close to it: 7.62x51 (.308), .30-06, 6.5 Creedmoor and .303.
  - Rifle rounds take sustained fire into one limb (about 10 5.56 rounds into a living shin),
    and pistol rounds hardly ever.
  - A corpse keeps taking it: about 16 rifle rounds into a dead man's leg takes it off.
- **Losing a limb alive** is an arterial bleed a tourniquet stops, with the shock of it: he's
  dying or out.
- The severed piece lands in the same place for every player, as a blast's does.
- All the numbers are in one table (BodyDeform.GUNFIRE), Proposed.
### M1014 model rework (Captain, v0.5.0: "the m1014 is the wrong color and doesnt look right")

#### Fixed
- **The M1014 is matte black** and reads as the real gun. Its forend, stock tube and handle used
  the grey gun colour, which looked grey-tan in daylight. It now has a slim barrel with the
  front blade in its protective wings, and the extended magazine tube runs to 2.5 cm from the
  muzzle under a barrel clamp with its sling loop. The receiver has a Picatinny rail with the
  ghost ring between its ears, the bolt and its handle in the ejection port, the bolt release,
  and the loading port with the carrier and shell latch. It has a cross-bolt safety, a pistol
  grip and the telescoping stock out on its tube. It is 1 m long.
- **The Mossberg 590's furniture is black** too (it was the same grey), and both pump guns show
  a bright bolt in the ejection port.
### Gore fixes (Captain, 2026-10-21)

#### Fixed
- **Hair no longer goes pale or blue.** Pallor and blue lips were keyed to the uniform's default
  skin colour, not the face's own skin and hair. Some hair shades matched the default mouth and
  lip colours and took the tint. Each mesh's overlay now uses its own colour scheme, and hair,
  brows and eyes are never tinted. Blue lips now also show on the face's moving mouth.
- **The first headshot leaves a wound.** A killing head hit killed without recording a wound, so
  it drew no hole, blood or brain spatter. Only later shots into the corpse showed.
- **An RPG to the head leaves a neck, not a crater.** A warhead hit on the head, face or neck now
  takes the head (pulped by a filling big enough to gib, flung off by a smaller one), chars and
  peppers the chest, and leaves the body whole. Before, it gibbed him and carved big craters in
  the torso at the collar. Every head cut now leaves a neck stump about 5 cm tall (it was about
  2 cm and mostly torn away), opened like a limb: skin, fat, flesh and the spine at its core.
- **A gibbed torso lands the way it's thrown.** After an RPG in the chest blew everything off,
  the torso spun and landed any way up (often face down). Now, hit from the front, it goes
  over onto its back; from behind, onto its front. Four causes:
  - The death collapse push meant for a body standing on its legs spun a lone torso like a top.
    A body with no lower legs no longer gets it.
  - The burst's throw skipped the man it went off on. A direct hit now throws him away from it.
  - Pieces flying off hit their own torso on the way out. They no longer collide with their
    own body or with each other.
  - A cut limb's joint held the falling torso for one more physics step. It now goes at once.
  A torso left standing on its neck is tipped over too.
- **Wound marks go with a cut-off limb.** Holes and blood trails past the cut stayed hanging in
  the air where the limb had been. Now only the marks on what's left of the part are drawn.

### Gun styles: the new SMGs, shotguns and pistols get their own models (items expansion follow-up)

#### Added
- **SMG models**: the MP5 (cocking tube with its handle on the left, curved magazine, two-strut
  stock), the MP5SD (integral suppressor), the UMP45 (squared polymer body, straight magazine,
  folding skeleton stock), and the MP7 and Uzi with the magazine up the pistol grip. An empty
  reload slaps the locked-back cocking handle home.
- **Shotgun models**: the Remington 870 (wooden pump and stock) and Mossberg 590 (synthetic, heat
  shield) with a magazine tube under the barrel and no magazine well, racked by the pump; the
  M1014 with its charging handle, pistol grip and collapsible stock. Shells load through the top,
  like a bolt-action's clip.
- **Pistol variants**: compact (Glock 19), all-steel hammer pistols with wooden grips (M1911,
  Beretta M9, CZ 75, TT-33, P226) and a compact steel one (Makarov PM).

#### Changed
- These guns used to borrow the C8, Mosin or single pistol model at their real length. The
  G36C, Vityaz, Saiga-12, P90, AUG, Lee-Enfield and SKS keep their families (carbine, AK,
  bullpup, bolt-action), which match the real guns closely enough.
### A squadmate no longer stays behind after clearing a building on his own (2026-10-21)

#### Fixed
- **Squadmates who clear a building on their own follow you again afterwards.** When you walk
  into a building, idle squadmates stack up and clear it. A man who finished his corner used to
  stay put for good, as if you'd ordered him to hold there. He now goes back to following you. A
  clear you order still ends with them holding where they got to.
### Breacher role (Captain, 2026-10-20: "we need breacher roles for the player team", "they use breaching charges")

#### Added
- **Breacher** role (BRC), pickable in the main menu, at join, on the loadout screen and in the
  roster like the other roles. It takes a free non-medic slot, the way anti-tank and the heavy
  gunner do. Kit: Mossberg 590A1 breaching shotgun with five speed loaders in shell pouches, an
  M17, three breaching charges, three flashbangs and ear protection. An LX-3 preset too.
- **AI breachers lead building entries.** The breacher goes first in the stack and makes the way in:
  - In Aware or Combat he sets a **breaching charge**. He walks to the wall on the far side of
    the doorway from the stack, sets it, falls back, and the team goes in through the hole.
  - Out of charges, he **shotguns the hinge side of the door frame** if an enemy is known
    inside, and **kicks** it otherwise.
  - In **Stealth** he eases the door open. He uses a charge only when ordered.
  - A **flashbang** goes in after the breach (a frag if there's no flashbang and an enemy is
    known inside). There's never a bang in Stealth, on a quiet order, or with a civilian known
    inside.
  - This covers ordered clears, town clears and a squad clearing an enemy-held building itself.
  - A squad with no breacher clears the way it does today.
- **Human breachers**: when a breacher player orders Clear, the squad stacks and holds, as on
  "clear on me", until he breaches. That's his charge going off by the door or his shotgun into
  the frame. Then the bang goes in and they enter. If he just walks in, they follow.
- **Command menu > Clear**: "kick it in" (8), "shotgun the door" (9) and "quietly (eased open,
  no bang)" (0). With no breacher, the first man in the stack kicks. Voice: "kick it in",
  "shotgun the door", "charge and clear", "clear it quietly".
- **Command menu > Team > Assign role** (9 6): the selected AI squadmates take on a role.
  Breacher is key 1. Their kit stays what it is. Voice: "make breacher".

#### Fixed
- **Breaching charges on a wall cut a doorway.** Before, they left a big crater in the ground
  and a strip of plinth, fence or wall at the foot that AI couldn't walk past or over. Now the
  cut is 1.3 m wide and 2.2 m tall, from the floor at the wall's foot, through every material
  but steel. The ground isn't cratered. A charge set on the ground leaves a small crater.
- **A wall charge doesn't hurt the stack beside the door.** It throws no fragments out the side
  it was set from, and only half its overpressure.

### Items expansion: 214 new items (Captain, 2026-10-20: "we genuinely need more items like ive been harping about")

#### Added
- **41 guns**, all real-world, each with its own magazine and rounds:
  - Pistols: Glock 19, Beretta M9, CZ 75 B, Makarov PM, Tokarev TT-33, FN Five-seveN, Glock 18C
    (full auto), HK USP45.
  - SMGs: MP5A3, MP5SD6 (built-in suppressor), MP7A1, Uzi, PP-19-01 Vityaz, P90, UMP45.
  - Shotguns: Remington 870, Mossberg 590A1, Benelli M1014, Saiga-12. Each shell fires nine
    buckshot pellets, each traced on its own.
  - Assault rifles: SIG MCX, SCAR-L, G36C, AUG A3, Tavor X95, AK-12, AKMS, AK-105, AMD-65,
    vz. 58.
  - Marksman rifles: Mk 12 SPR, SR-25, M14 EBR.
  - Battle rifles: G3A3, FN FAL, L1A1 SLR.
  - Machine guns: RPD, Negev, MG3, M60E4.
  - Older rifles: Lee-Enfield No. 4, SKS.
- **32 ammo items** and **7 new rounds**: 9x18 Makarov, 7.62x25 Tokarev, 5.7x28, 4.6x30,
  .303 British, 7.62 M118LR match and 5.56 Mk 262 match.
  - New magazines: SMG, pistol, 7.62 battle-rifle and match, a 45-round RPK-74 magazine (the
    RPK-74 now takes it), G36, AUG and vz. 58.
  - Shotgun ammo: 12 gauge speed loaders, Saiga magazines and loose shells.
  - Charger clips for the Lee-Enfield and SKS, and an RPD belt drum.
- **33 gear items:**
  - 7 helmets: ACH, Mk7, 6B47, SSh-68, M1 steel, ECH (rated III), Altyn with visor.
  - 6 carriers: SPC, MBAV, 6B23, slick carrier, police IIIA vest, IOTV with side plates.
  - 3 chest rigs with no armour: Chicom, Smersh, D3CRM.
  - 4 packs: sling bag, daypack, 30 L assault pack, 60 L ruck.
  - 5 pouches: SMG mags, shotgun shells, canteen, large GP, 7.62 mags.
  - 4 plates: SAPI III+, XSAPI IV, light PE III+, ceramic side plate.
  - 3 ear protectors (ComTac, Sordin, foam earplugs). They work like the existing ear pro.
  - A ghillie suit: lying or crouched, you take half again as long to spot.
- **21 attachments** on the existing mounts:
  - 9 optics: Kobra, Romeo5, T-2 with a 3x magnifier, PSO-1, HAMR, SUSAT, ELCAN C79, Strike
    Eagle 1-6x, ATACR 5-25x.
  - 4 suppressors: 9mm, .45, AK (PBS-4), short 5.56.
  - Handstop, stubby grip, Harris bipod, grip pod.
  - X300 and TLR-1 lights, a green laser, a PEQ-2 IR laser.
- **12 consumables** with a real effect. Right-click > Drink, Eat, Take or Use (or double-click)
  in the inventory.
  - Energy drink, caffeine tablets: stamina comes back faster for half an hour or so, and the
    heart rate goes up a little.
  - Ibuprofen, paracetamol: a little pain relief. Together they take at most 0.25 off, against
    morphine's 0.5 a dose. They don't sedate.
  - Bottled water, electrolyte sachets, MRE, IRP ration, energy bar, canned meat: stamina comes
    back a little faster. Food and water aren't tracked yet, so nothing goes hungry.
  - AA and CR123A batteries: recharge an NVG fully (the mounted one, else the flattest you carry).
- **75 barter, materials, valuables and documents**, Tarkov-inspired:
  - 30 materials: tools, electrical parts, a graphics card, drone parts, vehicle parts, weapon
    parts. They are salvage, so rebel support upgrades can use them.
  - Vehicle parts in the stash (spark plugs, bearings, an alternator, oil...) take up to half
    off a motor pool repair.
  - 27 barter items: household goods, medical supplies, keys, and clothing (gloves, balaclava,
    shemagh, ballistic glasses and goggles, knee pads, GP-5 and M50 gas masks). Gas masks are
    barter because there is no gas mechanic.
  - 13 valuables: rings, chains, earrings, phones, a laptop, a camera, beads, a statuette.
  - 5 intel documents: ID cards, a shipping manifest, bank slips, photographs, letters.
- **Every new item is in the loot tables, by rarity.**
  - The site boxes, pools and body pockets all take them.
  - Cheap finds come two or three to a bundle.
  - Strongboxes hold only valuables and papers.
- **Army kits.** The Iranian Concord kit fields G3A3s, the Russian kit an AK-12, and US allies a
  Mk 12 marksman.
- **Art.** New guns use the existing families at their real length:
  - the MP5 and UMP on the short carbine;
  - the Vityaz and Saiga on the AK;
  - the P90 and AUG on the bullpup;
  - pump guns on the wooden bolt frame.
- New magazines, rounds, phones, laptops, papers, electronics and headsets have their own
  shapes; the rest use the generic box. Shotguns have their own report.

### Loot on bodies (Captain, 2026-10-20: "we stil havent gotten loot variety in somehow")

#### Added
- **Every enemy carries 1 to 3 things of his own** besides his kit, rolled by rarity from a new
  "pockets" pool. Different on every body and every deployment, the same body the same.
  - Common: cash, cigarettes, bandages, loose rounds, SIM cards, hashish, zip cuffs.
  - Uncommon: phones, documents, grenades, morphine, watches, gold coins, radios.
  - Rare: optics, attachments, ledgers, maps, gems, cash bundles.
  - Very rare: a laptop, NVGs, a sat phone, a cash brick.
- **Leaders carry their intel too** (orders, maps, phones, laptops).
- Very rare finds only drop in hot zones, as for site boxes.

### Conscious but dying, and wounded behaviour (Captain, 2026-10-20: "a conscious but dying state ... animations and sounds", "they dont really do wounded things")

#### Added
- **A conscious-but-dying state.** A soldier is dying while still awake when any of these hold:
  - about 28% of his blood is gone and a wound is still bleeding;
  - his oxygen is failing (SpO2 under 88%).
- **What dying does:**
  - He collapses to the ground. Lying still, he writhes with a hand pressed to the wound and
    reaches out as he weakens; he can only drag himself along slowly.
  - He breathes hard, with a laboured breath you can hear nearby, and cries out now and then.
    Both sides hear the cries.
  - He can't stand or fight, but he can still treat himself and call for a medic.
  - AI who are dying treat themselves if they can, otherwise stay down and call for help.
  - It ends a few seconds after the cause is treated, so a tourniquet brings him back out of
    it. Untreated, it runs on into unconsciousness, arrest and death as before.
  - Players get a one-time prompt telling them what to do. The squad sees "Dying" in his status.
- **Wounded but up:**
  - pain hunches the shoulders and drops the head (less while aiming);
  - breathing quickens and deepens with blood loss, not just tiredness.
### Treatment you can see on the body (Captain, 2026-10-20: better wounding, more realistic body wounds)

#### Added
- **Tourniquets show.** A black strap high and tight, 12 cm above the wound (as high as the limb
  allows for a wound further down), with its windlass locked on the outside of the limb, the red
  tip hanging off and a white label with the time it went on written in 0.5 cm digits. A second
  one sits beside the first. They are gone once they come off.
- **Splints, the pelvic binder and the sling.** A splint runs along the broken limb (orange out,
  blue at the edges) under three cravats. A broken pelvis gets a black binder round the hips with
  its buckle at the front. A broken collarbone gets a sling across the chest.
- **Dressings look like what was used.** A pressure bandage is a cream elastic wrap with its
  pressure bar over the hole. Packed gauze is white, bulges out of the wound and has a loose tail.
  A chest seal is a square patch with a dark border and a valve. Before, all three were the same
  beige pad.
- **IV and IO lines and the bag.** An IV is taped in the forearm or shin, the hub coloured by its
  gauge. An IO has its round patch on the sternum. While fluids run, the bag hangs on the
  casualty's chest (on the vest front with one on), a line runs from it to the site, and the bag
  empties as it goes in. A pressure bag adds its blue cuff.
- **The NPA** shows as a small flange at the nostril. **The blanket** wraps the trunk, arms and
  legs in creased foil.
- **Open fractures show bone** at the wound until the wound is dressed.
- **Burns scorch the body.** Patches of skin and uniform char and darken, raw red at the edges,
  roughly over the burned share. Burn dressings cover part of them as they go on.
- **Pallor, blue lips, blood at the mouth, shivering.** Skin greys from 15% of blood lost and is
  ashen by 45%. Lips go blue-grey under 88% SpO2. A casualty coughing blood
  has it at the mouth and down the chin. A hypothermic casualty visibly shivers. These were text
  cues only before.
- **Bloody hands.** Whoever treats a wound that is bleeding, or has bled, gets blood on both
  hands. It dries darker after a minute and is gone after 7 minutes.
- **A drag smear.** A bleeding casualty dragged, or crawling, leaves a continuous smear on the
  ground under the wound. It is capped at 160 cells per body, oldest first, and lasts as long as a
  pool.
- All of it is drawn on every peer from the replicated wound and treatment state, at the model's
  0.5 cm voxel scale. New `devices` test suite; the net test checks the devices on a client.
### Fingers (Captain, 2026-10-20: more realistic character models)

#### Added
- **Hands have fingers.** Every soldier's hand is a palm, four fingers and a thumb in 0.5 cm
  voxels, with knuckles and a slightly cupped palm. Women's hands are smaller and slimmer.
  Contractors and the other armies wear gloves (a knuckle guard, a palm patch). The militia and
  civilians are bare-handed, with nails and knuckle creases.
- **Hands grip what they hold.** On a weapon the firing hand wraps the pistol grip, with the
  index straight along the frame. It moves onto the trigger while aiming and for a moment after a
  shot, and squeezes on each shot. The support hand cups the handguard. In a reload it takes the
  magazine, pinches the charging handle, presses the catch and opens on a feed cover. Holding
  anything else (straps, handles, the fast-rope, a radio, treatment kit) the hand closes round it.
  Planting on the floor it opens. The forearm turns so the palm faces the grip.
- **First person shows the same hands**, and the trigger finger moves when you fire.
- For whoever puts props in a hand: `CharacterModel.set_hand_pose(hand, pose)` holds a pose, and
  `hand_anchor(hand)` is a node at the hand's grasp centre to parent a prop to.

#### Changed
- Each hand pose is a whole forearm mesh, swapped as the hand's work changes. That costs no extra
  nodes or draw calls, and the meshes are shared by every body in the same colour scheme. A posed
  forearm is about 2,300 to 3,200 triangles. The common poses are built ahead on a worker thread
  as a level starts. Far off, the trigger squeeze isn't drawn.
### Medical care: the kit in your hands, a first-person medic view, the casualty reacts (Captain, 2026-10-20)

#### Added
- **Treatment kit in the hands.** Every treatment now shows what it's done with, in 0.5 cm voxels,
  moving through its steps:
  - A bandage roll shrinks as it unwinds, its tail running onto the turns building up on the limb
    over the pad.
  - Gauze runs off its fold into the wound, then both hands hold pressure.
  - A tourniquet: the strap pulled round, the band tightening as the windlass turns, then the rod
    clipped. The last turn lands just as the clip phase starts, and the bleeding stops at the end
    of it.
  - A chest seal's backing is peeled off, then the seal is pressed on.
  - The decompression needle goes in at the second intercostal space and the stylet comes back
    out, leaving the catheter.
  - The autoinjector's safety cap comes off before the jab, and it's held in. Adenosine uses a
    syringe whose plunger goes down.
  - An IV catheter slides in along the vein and is taped. The IO driver goes in at the sternum.
  - The saline or blood bag is held up with the line running down to the access site. The bag
    level follows the fluid actually going in, and a pressure bag's bulb is pumped.
  - A splint is bent into a U, then laid along the limb and wrapped.
  - The defibrillator sits beside the casualty, with pads and cables onto the chest.
  - The surgical clamp uses a hemostat and forceps, with the surgery kit open on the ground.
  - The foil blanket opens out, and the NPA and the pelvic binder's handles show too.

  Everyone sees it, squad AI medics included, and it's gone when the treatment ends.
- **The hands work on the wound itself.** The hands now go to the wound on the casualty's skin,
  or to the right spot for the treatment, following the body if it moves:
  - the sternum for CPR,
  - the outer thigh for an injector,
  - the second intercostal space for the needle,
  - high and tight on the limb for a tourniquet, with the hands going round the limb.

  Before, they worked at the middle of the body part.
- **First-person medic view.** While you treat someone, or yourself, the weapon leaves the view
  and your own forearms, hands and kit are in it. The view goes down with your kneel and, for a
  moment at the start, turns to the work.
- **The casualty reacts:**
  - a wince as a tourniquet tightens or a wound is packed (if they're awake),
  - settling down after morphine (also as their morphine level rises),
  - a gasp as the needle goes in,
  - the chest going down under CPR,
  - a jolt on the defibrillator's shock.
- **Treating yourself:**
  - A tourniquet or bandage on your own arm is done one-handed, with the hurt arm held out and the
    body turned to it.
  - On your own leg you go down on a knee and lean over it.
  - An injector goes into your outer thigh standing.

  Treatment times are unchanged.
### Real faces, and a different person in every uniform (Captain, 2026-10-20)

#### Added
- **Heads with real proportions**, still 0.5 cm voxels: a skull, a brow ridge over eye sockets,
  a nose with a bridge and a tip, cheekbones, a jaw and chin, ears, and hair and beards with
  volume. Helmets, NVGs and IFF marks fit as before.
- **Eyes** with whites, irises and pupils. They blink, glance about, look up and down with the
  aim, narrow in bad pain, and close when a soldier is knocked out or dead.
- **Expressions**: neutral; strain when hurt, down, or carrying or dragging someone; mouth open
  while calling out or screaming; slack when out cold or dead, and when gasping for breath.
  The eyes, mouth and brows are small parts swapped whole: nothing is animated voxel by voxel.
- **Every soldier is his own person**: skin tone, hair style and colour, eye colour, beard or
  stubble, jaw, chin, nose, brow and ears, a slim, average or heavy build, and a height range,
  for men and women. Soldiers look like their nation's people: an American squad is mixed, a
  Chinese one East Asian, and the region's insurgents mostly bearded. Uniforms stay the
  faction's.
- **The same face everywhere**: a soldier's look comes from who he is (the spawn's identity),
  so every peer draws the same person; it rides in the spawn, the replicated state and body
  records. Company members keep their face all campaign (a look seed on the roster, kept
  through saves), and each player's main character has their own.
- Civilians, HVTs and hostages get faces too, matching the skin of their bare hands.

#### Changed
- A new face's head is built on a worker thread, so a squad or garrison appearing doesn't stall
  a frame; its head shows once built (a moment after spawning). Face parts aren't drawn past
  30 m.
- A broader build widens the body's meshes about each part's own axis, so poses, hands on the
  weapon and hitboxes stay where they were; the trunk's hit shape widens to match.

#### Fixed
- **The muster line shows the company's people as themselves.** Members standing at the base
  came out with a random name tape, nationality and body; they now carry their roster identity
  and face, as they do in the field.
- A dragger's hands stay on the casualty's straps when the two are different heights.
### Treatment you can see on the body (Captain, 2026-10-20: better wounding, more realistic body wounds)

#### Added
- **Tourniquets show.** A black strap high and tight, 12 cm above the wound (as high as the limb
  allows for a wound further down), with its windlass locked on the outside of the limb, the red
  tip hanging off and a white label with the time it went on written in 0.5 cm digits. A second
  one sits beside the first. They are gone once they come off.
- **Splints, the pelvic binder and the sling.** A splint runs along the broken limb (orange out,
  blue at the edges) under three cravats. A broken pelvis gets a black binder round the hips with
  its buckle at the front. A broken collarbone gets a sling across the chest.
- **Dressings look like what was used.** A pressure bandage is a cream elastic wrap with its
  pressure bar over the hole. Packed gauze is white, bulges out of the wound and has a loose tail.
  A chest seal is a square patch with a dark border and a valve. Before, all three were the same
  beige pad.
- **IV and IO lines and the bag.** An IV is taped in the forearm or shin, the hub coloured by its
  gauge. An IO has its round patch on the sternum. While fluids run, the bag hangs on the
  casualty's chest (on the vest front with one on), a line runs from it to the site, and the bag
  empties as it goes in. A pressure bag adds its blue cuff.
- **The NPA** shows as a small flange at the nostril. **The blanket** wraps the trunk, arms and
  legs in creased foil.
- **Open fractures show bone** at the wound until the wound is dressed.
- **Burns scorch the body.** Patches of skin and uniform char and darken, raw red at the edges,
  roughly over the burned share. Burn dressings cover part of them as they go on.
- **Pallor, blue lips, blood at the mouth, shivering.** Skin greys from 15% of blood lost and is
  ashen by 45%. Lips go blue-grey under 88% SpO2. A casualty coughing blood
  has it at the mouth and down the chin. A hypothermic casualty visibly shivers. These were text
  cues only before.
- **Bloody hands.** Whoever treats a wound that is bleeding, or has bled, gets blood on both
  hands. It dries darker after a minute and is gone after 7 minutes.
- **A drag smear.** A bleeding casualty dragged, or crawling, leaves a continuous smear on the
  ground under the wound. It is capped at 160 cells per body, oldest first, and lasts as long as a
  pool.
- All of it is drawn on every peer from the replicated wound and treatment state, at the model's
  0.5 cm voxel scale. New `devices` test suite; the net test checks the devices on a client.
### Blast dismemberment and synced severed pieces (Captain, 2026-10-20)

#### Added
- **Explosions tear bodies.** Grenades, charges, mortar rounds, RPG and AT4 rounds tear the bodies
  near them, by distance and the size of the charge. A close blast takes one or more limbs. A
  blast right against someone blows them apart: head, arms and legs off, the torso torn open.
  Fragments pepper the side facing the blast with small holes, and that side is scorched black.
  The Captain's rule holds: while someone lives, a blast takes at most a foot or forearm, or
  leaves a thigh or upper arm hanging. Either way it's an amputation a tourniquet stops. Worse
  happens only to the dead, or to someone the blast kills outright. Corpses near a blast are torn
  too.
- **.50s and vehicles.** A .50 takes the limb or head it hits. A heavy vehicle driving over a body
  crushes what it rolls over; dead, a heavy one crushes the head. A vehicle that hits someone hard
  tears the side it hit.
- **Inside a wound.** Deep craters and stumps show torn skin, then fat, red flesh and white bone
  at the core of a limb. The skull shows under the scalp and ribs in the torso. Bone sticks out
  of a stump a little.
- **Limbs hanging by tissue.** A dead limb torn up nearly enough to come off hangs by a strip of
  tissue, swung off the stump. More damage cuts it through, and what hung drops.
- **A gore setting** (Settings, Video): Full (the default), Reduced (wounds and lost limbs, but no
  bone, fragment pocks or flying bits) or Off (bodies drawn whole). It only changes how your own
  game draws bodies.

#### Fixed
- **Severed pieces land in the same place for everyone.** The host settles each piece and sends
  where it lies; other players' pieces move there, and anyone joining later sees them there too.
  Pieces have colliders fitted to their shape instead of a box. A helmet on a head that comes off
  drops beside it as an item you can pick up.
- **Corpses no longer prop up on a cut-off limb.** A cut limb's ragdoll part goes with it, and
  the part it was cut from shortens to the stump, so the body lies on what's left.
- **Torn bodies survive a zone save.** A saved body comes back with the same holes and cuts, its
  pieces where they lay.
- Rebuilding torn body parts is capped at a few a frame across all bodies, so a big blast
  doesn't stall the game.
- **Bodies no longer die standing up.** A body that drops goes limp: the knees and hips give,
  the trunk folds, the head lolls. Nothing holds it upright, so a corpse no longer settles kneeling
  or propped on stiff legs. It falls the way it was pushed: shot from the front it goes back,
  running it pitches forward, a blast throws it away from the burst. Knees and elbows never bend
  the wrong way, even when thrown. Every player sees it come to rest the same way.
### Terror groups follow-ups: named leaders, drug labs and contraband (2026-10-20)

The follow-ups from docs/terror_groups.md section 9. Every name is made up.

#### Added
- **HVT jobs go after named leaders.** An HVT capture or manhunt job against a group is after the
  next of its leaders still free, by title and name: "HVT capture (the Chemist)", "Capture the
  Chemist (his name) and bring them to extraction alive". The brief opens with who he is.
  Winning the job takes that leader down, in any zone, and the next job names the next one.
- **Leaders dress for their part.** Each leader is a commander, a financier or a bomb maker
  (the Bookkeeper wears a dark suit, the Chemist work clothes).
- **Each group names its own sites.** A raid or supply-line cache is an IED workshop for the Ashen
  Banner and the Valley Shura, and a drug lab or a warehouse for the Kestrel Cartel and the
  Saltline Syndicate. The same site always has the same name.
- **Cartel contraband.** A raid, sabotage or supply-line job against a cartel has a box of its
  goods (hashish, captagon, heroin bricks, counterfeit dollars) beside the target. Every third man
  of a cartel garrison carries some in his pockets.

#### Changed
- **Vantage and the Eastern Concord Forces fight by their own doctrine** (PMC and regular army)
  wherever they are, not by the doctrine of the zone's people. Vantage's racing team now counts
  as Vantage's men, whoever holds the zone.
- **Fewer suicide bombers** (Captain). Once the Banner or the Shura is pushed or hunting the
  squad, the 10% chance of a bomber is rolled every 3 minutes instead of every 30 seconds: about
  one per half hour instead of one per five minutes, and still at least 10 minutes apart.

### Terror groups, cartels and a living war (Captain, 2026-10-20)

Design and the Captain's calls: docs/terror_groups.md. Every name and flag is made up.

#### Added
- **Five new enemy groups** hold ground on the map, each with its own kit, clothes, guns,
  doctrine, flag, leaders and radio chatter:
  - **the Ashen Banner**: a jihadist network with foreign fighters. Its local men wear dark plain
    clothes; its foreign fighters wear their own camo and helmets. It fights almost to the last
    man. Red on the map.
  - **the Valley Shura**: a local Islamist insurgency in the inland villages. Its men wear village
    clothes and old rifles. It hits from range and slips away. Red.
  - **the Saltline Syndicate**: a coastal smuggling cartel in the harbours. Orange.
  - **the Kestrel Cartel**: an inland drug cartel in the river valleys. Orange.
  - **the Highland Free Front**: a separatist cell on the moors that fights the Eastern Concord
    first. It starts only Distrusted, so it can be won over. Orange.
- **Suicide bombers and VBIEDs** now come from the Ashen Banner and the Valley Shura (Captain),
  no longer from Black Ridge.
- **A living war.** Zones change hands over the days, about one every three:
  - each faction fights for what it wants: oil, airfields and HQs for the Banner; villages,
    mosques and recruits for the Shura; harbours, crossings and routes for the cartels; Black
    Ridge for its home valleys;
  - at most three fronts are open at once;
  - the war is saved in the campaign and plays the same way every time;
  - a faction's last zone can be sieged but never falls to another faction;
  - the company wipes a faction out by taking its last zone's HQ and QRF bases and its leaders;
  - fronts can reach the company's own zones (a defence job goes up), and the FOB's zone can be
    sieged but never falls.
- **The player shifts the war:**
  - contract wins, kills and HQ and QRF bases taken out weaken a faction and push its fronts;
  - high rebel support starves Black Ridge and the cartels in that region;
  - at the top tier of rebel support, the locals take up arms themselves.
- **The player sees the war:**
  - a local stringer reads the overnight news on the radio, and the world map has a War news
    panel;
  - the map draws each holder's flag, front arrows and contested hatching, and its tooltip says
    who is attacking whom and why;
  - a contested zone opens with the attacker already assaulting a site, and part of the zone's
    sites held by its men;
  - in a contested zone, villages are half empty and refugee families walk out to the safe side;
  - fictional flags fly at each holder's compounds, outposts and checkpoints;
  - each group's radio net has its own lines.
- **Contracts follow the war:** a job goes up on every front, and a war job on every zone that
  just flipped. Board contracts are against the zone's holder 70% of the time.

#### Changed
- **Black Ridge is a regional militia.** It holds 4 of the 22 contract zones and Black Ridge hills
  (it held every zone before), and its share of contracts falls from about a third to a fifth.
### The M320 and a breaching shotgun (Captain's list for cghath, 2026-10-20: "Not built yet / Weapons and items")

Closes the list item "an M320 underbarrel grenade launcher and a shotgun".

#### Added
- **M320 Grenade Launcher** (`m320`, $1,600 proposed): an underbarrel attachment for railed rifles,
  mounted from the inventory like a grip (not on machine guns or sniper rifles). **4** (new key,
  rebindable; on the pad wheel as "Underbarrel / shells") switches the trigger to it and back;
  **R** then loads one grenade by hand (about 3 s), **Fire** lobs it. The grenade flies the
  launchers' own projectile with gravity, so it arcs: aim high for range. The loaded grenade is
  the launcher's own state: it stays in when the M320 comes off, goes back on, the gun is stowed,
  dropped, saved or looted, and every peer sees it. The HUD's ammo readout shows the grenade in
  it and the ones carried while the trigger is on it.
- **40 mm grenades:** M406 HE (`round_40mm_he`, $45) bursts through the existing warhead code
  (blast within about 3 m, fragments to about 10 m, a small crater) but only past 14 m; closer,
  it hits like a stone and doesn't go off. M714 smoke (`round_40mm_smoke`, $35) puts a white
  smoke cloud where it lands.
- **M870 Pump Shotgun** (`m870`, $900): a six-shell tube, pump action (one shot a pull, about 1 s
  to work the pump). **R** loads shells one at a time (about half a second each) until the tube
  is full; firing stops it. **4** picks which shell R loads. Shells (prices proposed):
  - **00 Buckshot** (`shells_12g_buck`, $2): nine pellets, each its own round through the
    ballistics, spread inside 1.6 degrees.
  - **Slugs** (`shells_12g_slug`, $2): one heavy round (IIIA).
  - **Breaching Rounds** (`shells_12g_breach`, $3): at a wooden or sheet-metal door or wall
    within 2.5 m they blow a hole through it, on a smaller scale than a breaching charge does
    (concrete only chips). At a locked box they shoot the lock off. Anything else, they hit as
    a weak, short-ranged round.
- The **grenadier** role's kit (data/roles.json) now has the M320 on his M4, with 8 HE and 2
  smoke grenades. A kit's gun attachment goes on the first gun in the kit that takes it.
- Weapon lights fit the shotgun. New sounds: the shotgun's boom, the M320's thump, a shell going
  in, the pump.
- Tests: weapons (data, buckshot pattern, an arcing HE burst that hurts a man near it, a dud
  inside the arming distance, smoke, buckshot/slug/breaching shots, shell-by-shell loading and
  firing stopping it, save/load and a peer's copy of both); attachments (the M320's grenade
  stays with it on and off the gun); armor (the two new rounds on the ladder).

#### Not yet (for the Captain's side and Claude)
- **Held models and poses (Captain's files):** carried in hand, the shotgun still shows the
  generic rifle model (VoxelArt has no `shotgun` style yet), and the M320 isn't drawn under the
  rifle (attachments under the barrel aren't drawn on the held gun at all yet). The ground models
  for both are new in ItemArt. Both use the rifle hold pose.
- **AI:** the AI grenadier carries the M320 but doesn't fire it (docs/audits/followups.md F-130),
  and an AI with a shotgun would see no spare ammo (F-131).
### Dog tags, the memorial wall, the death benefit, the shared triage log (Captain's list for cghath, 2026-10-20: "Campaign" and "Medical")

#### Added
- **Dog tags.** Every company soldier wears tags: your squadmates, hires and players. On a
  fallen squadmate's body, Left Ctrl > **Take dog tags** puts them in your gear. You have to be
  at the body as it lies, the same as looting.
- **Tags decide KIA or MIA.** Carry his tags out at extraction, or bring his body, and he's
  recorded killed in action. His name goes on the memorial wall and his death benefit is paid.
  Without his tags or his body he's missing in action. He gets no recovery contract (there's
  nobody to bring back alive) and stays on the books until either:
  - his tags come home on a later deployment (then he's KIA), or
  - 7 days pass after he fell (Proposed). Then he's declared dead, his benefit is paid, and he
    goes on the wall as "missing".
  The tags go to the company's records, not into your kit or the stash. A body taken by the body
  cap leaves its tags where it lay.
- **The memorial wall**: a new Memorial tab on the base screen, and a wall to use in the LHD's
  hangar (port side). For each of the fallen it lists their name and callsign, role, the day,
  the zone, the contract, how many missions they served and "Tags recovered" or "Missing". It
  also lists anyone missing after they fell who hasn't been declared dead yet. It's saved with
  the campaign.
- **The shared triage log.** The medical menu's log now lives on the casualty, so everyone
  treating him sees the same entries: who did what, and when (by the zone's clock). Players' and
  AI medics' treatments and triage cards go in it. It's kept by the host and reaches every
  player, late joiners included. It stays with the casualty when he's carried or dragged, across
  a crossing and through a save. Before, the log showed only what you yourself did while your
  menu was open.

#### Changed
- **The death benefit is paid once per man, when his death is confirmed** (his tags came home,
  or he was declared dead or written off). It's a line of its own in the debrief and in the
  books ("Death benefit: Reaper (...)", a "Death benefits" kind on the Books tab), with a notice
  for everyone. Before, every friendly body in the zone was counted at each debrief, so a body
  left from an earlier deployment could be paid for again. Raids pay it too now. A squadmate
  written off after a failed recovery now costs the benefit as well.
### Fire support: artillery and mortar fire missions, a recon UAV, the forward observer (Captain's list, 2026-10-20)

Closes "Vehicles and air: player artillery and UAV calls" and "Campaign / mission types: forward
observer". Learning from how real call-for-fire works and from Arma's artillery, not copying
either. Every number is Proposed (data/fire_support.json, data/prices.json).

#### Added
- **Fire missions** (Support > Fire support, or the fire mission panel for typed corrections and
  grids). Two firing units fire from off the map:
  - an 81 mm mortar section, lent by any employer you stand at least Neutral with;
  - a 105 mm battery, from Trusted, inland only (it sits at the inland FOB).

  How a mission goes:
  - **Call it** on your map marker, on where you look, or on a typed grid. Through binoculars the
    point is lased: it reaches 2.5 km and the first round lands closer.
  - **Adjust.** One adjusting round lands with the guns' starting error. Correct from the burst
    along your line to the target ("add 50, left 25"), as often as you need.
  - **Fire for effect:** up to 8 mortar or 6 battery rounds, HE or smoke.

  Rounds fly their real time of flight and land within a stated radius. HE uses the existing blast
  (people, craters, the enemy hearing it) and hits vehicles near it. Smoke lands as white clouds.
  The radio calls "shot" and "splash".

  Limits:
  - **Danger close:** with friendlies within 150 m (mortars) or 250 m (battery) of the aim, the guns
    wait until you confirm.
  - **Cost:** $450 a mortar round, $1,500 a battery round, from the support budget first, then cash.
  - **Cooldown and ammunition:** a cooldown after each fire for effect, and a ration of rounds per
    deployment. The deployment keeps both, as it does the rebels' call-ins.
- **Recon UAV** (Support > Fire support > Recon UAV, $8,000):
  - It flies in from where the supports come from, then circles a point 280 m up for 10 minutes.
  - Hostiles its camera can see are tagged for the squad through the existing tags (red marks, the
    map). It judges what it sees the way the AI's spotting does (stance, movement, camo, foliage,
    weather). It sees in thermal, so night doesn't hide anyone.
  - "Open the UAV feed" shows its camera in a panel at the right of the screen.
  - Storms ground it, and send it home if they start while it's up.
  - Three hits bring it down, and a manned enemy AA technical in range can hit it. It has a
    15-minute cooldown.
- **Forward observer contract** (on the board at outposts, checkpoints, QRF bases, HQs and
  compounds, in contract and hot zones):
  - Get eyes on the target area from up to 700 m.
  - Bring the guns onto the 3-4 vehicles and weapon positions there.
  - Stay unseen.

  Pay goes by the targets the guns destroy: the first is the job, each further one a 25% bonus, and
  never being spotted another 20%. A target destroyed any other way fails and doesn't pay.
- A 105 mm HE warhead (data/warheads.json) for the battery.
- Tests: a new `firesupport` suite, in the default local list and CI. The forward observer is in
  `missions`, and the panel and the UAV feed are in `ui`.
### Demolitions: demo blocks, det cord, thermite, claymores, mines, chem lights (cghath, 2026-10-20)

Closes the Captain's 2026-10-20 list item "Not built yet: Weapons and items: mines and claymores,
demo blocks, det cord, thermite, chem lights". All numbers and prices are Proposed.

#### Added
- **Demolition block (C4).** Pick it with Shift+G and press G: a ghost shows where it goes on the
  surface you look at, within 2.5 m. R picks how it's armed: a 10, 30 or 60 s timer, a detonator,
  or det cord. Fire places it. It's a big blast: a wide hole in walls, people hurt by the blast
  and fragments, and a vehicle it's set on badly damaged (a charge in contact hurts a hull far more
  than one going off beside it). A sabotage target or cache it's set on is destroyed.
- **Det cord.** Arm a block or claymore on det cord and it's tied to your nearest block or claymore
  within 15 m, using one coil. When any one in the chain goes off, they all go.
- **Firing devices.** The M57 clacker (50 m of wire) and a radio remote (400 m). Pick one with
  Shift+G and press G: everything you armed on a detonator within range goes off.
- **Thermite.** Set it on a vehicle, a static gun, a cache or the ground. It lights after 3 s and
  burns for 8 s, with a bright flickering light, sparks and a hiss. Then a vehicle's engine is
  burnt out and the vehicle catches fire, a static gun is wrecked, a cache is destroyed. Anyone
  within a metre is burnt.
- **M18 claymore.** Set it on the ground, facing where you look. Fire it with a clacker or remote,
  on det cord, or on a tripwire 2 m in front (live after 10 s). Its fragments fly in a 60 degree
  fan out to 50 m; behind and beside it there's only the blast close in. Friendly fire is on.
- **AP mine (pressure).** Buried in the ground in front of you, live after 15 s. Anyone who steps
  on it, friend or foe, or a vehicle rolling over it, sets it off. The leg that stepped on it is
  wrecked. Our own mines and claymores are marked on the map.
- **Chem lights** in green, red, blue and IR. Throw one, or lob it to drop it close. It lies where
  it stops (or rides whoever it landed on) and glows for 30 minutes. Through night vision it's
  four times brighter and reaches further; the IR one shows only through night vision. For
  marking an LZ, a cleared room or a casualty.
- Blocks, claymores, mines and thermite leave blast gore on the bodies close by, as grenades and
  rockets do.
- **Picking things up again:** Left Ctrl at a placed block, claymore or mine offers "Pick up" from
  close by (not a lit thermite).
- Everything placed is seen by every player, late joiners too, and is saved with the zone. A zone
  left for a week keeps its mines and charges; the chem lights are out.
- In the base shop (Proposed): demo block 500, det cord 60, clacker 150, radio remote 600, thermite
  250, claymore 450, AP mine 200, chem lights 40 (IR 60). They sit with the grenades in the
  loadout menu.
- New test suite `demolitions`: placing, arming, the timer, the clacker and a det cord chain, a
  sabotage target destroyed by a block, a block on an MRAP, thermite disabling a technical, the
  claymore's fan hitting only in front, the tripwire and the mine (live only after their delay),
  a mine under a vehicle, picking up, chem light life and night-vision brightness, the zone save,
  and a client joining late that sees it all.

#### Changed
- Grenades and explosives share a band in the loadout menu: the breaching charge, blocks, mines,
  thermite and firing devices are listed with the grenades now (they were under Other).

### Stairs, the MG pit, a third-person reload error (Captain, 2026-10-20)

#### Fixed
- **Stairs are smooth.** Walking up stairs is one smooth climb instead of a jolt at each step:
  the view keeps its height for a moment after each step up and eases after the body.
- **The MG pit no longer places backwards at the base.** Defences with a front (the MG pit, the
  bunker, the mortar pit) now face out of the base wherever they stand, with their open side or
  way in toward the wire. The MG pit covering the gate had its wall to the base and its open side
  to the gate.
- **A script error in the third-person reload** fired every reload frame (the moving-parts list)
  and left the weapon's parts half split.

### Squad AI: stacking outside, clearing on you, longer order range, doctrines that act (Captain, 2026-10-20)

#### Fixed
- On a clear order, the stack forms outside the door. Before, a stack spot could be placed
  through the wall, inside the building, by a corner or an uneven wall. Each spot is now checked:
  outside the building, on the door's outer side, and not pulled through a wall. If not, it's
  moved further out or to the door's other side.

#### Added
- **Clear on me** (Command > Move > Clear > 7, or say "clear on me"): they stack outside the
  door, call "Stacked up. On you.", and hold until you go in. Then they follow you in, one after
  another. If you go down, they go in on their own.
- **Following you into a building**: walk into a building while your squad follows you (not in
  Safe mode, not at the base) and they stack on its door and clear it on their own. If they know
  of an enemy inside, they flashbang it first (a frag if no one has a flashbang), but never with a
  civilian or HVT seen inside. Walk away and they drop it and follow you again.
- Voice orders: "clear that building", "breach and clear", "clear on me".

#### Changed
- Orders reach 800 m: the crosshair finds a point or a target that far out (was 150 m for a point
  and 300 m for a target).
- Doctrines now shape how each side fights (AI bar G-15). Every number in the doctrine file acts,
  each as a lean against its side's usual doctrine:
  - the usual enemy (insurgents) and your squad (the PMC) fight exactly as tuned;
  - a regular army on the hostile side (the Eastern Concord's) reacts quicker, aims tighter,
    frags more often, pushes a bound sooner and hooks wider, and holds together longer;
  - the rival PMC among the hostiles is sharper again.
- AI bar G-04 marked done: the base of fire already checks its line before firing, standing over
  its cover or moving to a fire spot.
### Feel round 2 (Captain, 2026-10-20: his Star Citizen on-foot reference; Contractor learns from it)

#### Added
- **Pace on the mouse wheel.** On foot and not aiming, the wheel steps through four paces: a
  slow walk, a walk, a brisk walk and the jog (the default). Sprint stays on Shift. The HUD
  shows the new pace briefly. P still toggles quickly between the jog and the last slower pace.
  The command menu, the interaction menu, a grenade in hand and aiming still keep the wheel,
  and a free-spinning wheel moves one pace at a time.
- **Breath cycle with pauses.** A breath now goes in, holds at the top, goes out and holds
  longer at the bottom. The breath doesn't move the sight during either pause, so a patient
  shot can be timed into one. A breath takes 6 s with fresh legs and 2.5 s winded.
- **Carry states.** Sprinting, vaulting and mantling force the weapon low. Mantling now reaches
  other players too, so they see the weapon go low, and you can't aim mid-climb. Bringing the
  weapon up from low (the sprint carry or the low ready) takes up to x1.35 its usual ADS time.
  After a sprint the aim sways up to x2.5 for a moment (it builds over 1.5 s of sprinting and
  fades over 1.2 s).
- **Steadier head.** As the steps move the view, it turns slightly the other way to keep
  looking at a point 10 m ahead, so the world in front stays put while the body moves (only
  with head bob on).

#### Changed
- **Holding your breath scales with fitness.** Fresh, it lasts 10 s and the gasp after is 3 s.
  Spent, it lasts 1 s and the gasp is 6 s (it was 6 s / 3 s with a flat 2 s gasp). The gasp's
  extra sway eases off over its second half.
- **Third-person reloads match first person.** The weapon now moves on each reload's own keys
  (tipped and brought in for the magazine, the look and the seat, the bolt work), about 25%
  bigger so it reads at a distance. Near the view, the action locks back and slams home and a
  belt-fed's feed cover opens and shuts, as in first person. The parts are warmed with the
  uniform, so the first reload doesn't hitch. Far bodies (animation LOD) keep the cheaper
  magazine-only split. The phases already reach every peer and AI through the host's
  `_reload_began`; tests now check them over ENet and on an AI body.
### Story act 1 and the manhunt's markers (Captain, 2026-10-20: "the intel case doesn't tell you where dude is", "both markers show on the first map but not the second map")

#### Fixed
- **A manhunt's intel says where the man went.** Picking up the intel (the laptop, the papers or the
  compound's hard case) now gives his zone, his site and its grid reference. The radio says it, and
  his objective names the site.
- **Each zone's map shows only its own objectives.** The map used to show the briefing's list for
  the whole deployment: the man next door sat at the first zone's centre, and after the crossing
  the second map showed nothing. Now the map shows the deployment's live objectives that play in
  the zone you're in. The supply line and the convoy chase had the same problem and are fixed too.

#### Added
- **The story (docs/story.md).** The main arc is in four acts: the Vantage Group's conspiracy,
  uncovered through intel. Act 1, "The coast", is built: four story contracts for Meridian against
  Black Ridge, then Vantage.
  - **Paper trail**, an intel grab.
  - **The quartermaster**, a two-zone manhunt.
  - **The crates**, a two-zone supply line.
  - **Vantage point**, a raid for a Vantage team's ledger.
  - Each one unlocks once the one before it is done and its clue is found (Captain: "both").
  - The client's liaison calls each one in on the radio.
- **Clues and evidence.** Each story contract's intel adds a clue and evidence, and the evidence
  count opens each later act. Ordinary intel turned in counts too: 4 pieces make 1 evidence, and
  each Vantage ledger is 1, up to 3.
- **Leads on the contract board.** It shows the act, the evidence, what the next story contract
  waits for, and every clue so far.
- **Later acts and three faction arcs are data stubs**, waiting to be written.
### Economy overhaul (Captain, 2026-10-16: "too easy overall but mission expenses swing it negative fast")

Built from docs/economy_proposal_2026-10-20.md. Income is steadier and lower, the costs that
spiralled are capped, and the debrief and the base say where the money went. Details and the
measured before/after: docs/economy.md and the proposal's "Built" section.

#### Changed
- **Contract pay about a third lower** at every rating. Hot zones keep their better rate (x1.4).
  The no-civilian-casualties bonus is 5% (was 10%).
- **Hot zones start small.** The squad goes in on the one or two contracts it took for the zone
  (Captain: "with radios and villages entering hotzones with one or two objs will be good"). The
  zone no longer tops them up to 3-6 on arrival. More come in over the radio as the squad works,
  and from the villages: asking a villager in the hot zone you're deployed to hands you the
  locals' job live (once a zone a day), instead of putting it on the base board. Contracts taken
  on the spot pay nothing up front, all on completion.
- **Intel sells for what it's worth:** its own value, $500 to $4,000 (the HVT case $3,000), not
  a flat $6,000 a piece.
- **Wages and upkeep are paid every day,** a seventh of the week's bill. Each debrief shows its
  own days, and no debrief takes a whole week's bill at once. Loan installments stay weekly.
- **Capped shocks.** A helicopter lost on a support call costs a $15,000 deductible (was
  $30,000-40,000). Each bought respawn costs a quarter more than the last, never over $8,000 (was
  half more, no cap). The death benefit is $10,000 (was $15,000).

#### Added
- **Where the money came from:** a new debrief section lists advances, completion pay, bonuses,
  fines, clawbacks and what was sold in the debrief. Wages and upkeep show their days. The net is
  labelled "before loot", and a "Sold here" figure is added.
- **Books tab** on the base screen: running costs a day, loans and the next installment, the last
  7 days of money by kind, and the 20 newest payments. The base header and the contract board
  show costs a day instead of "weekly bill in N days".

#### Fixed
- **Intel could be sold twice.** Intel brought out goes to the debrief, never to the stash. The
  shop doesn't buy intel. A piece already debriefed is worth nothing if it is carried out again.
- **Hire-and-release for free kit.** Someone let go takes the kit they were issued. If it's
  missing, it comes out of the stash or its sell value is charged.
- **Radioing for contract after contract** no longer pays 30% of each up front.
### AI virtualization (Captain, 2026-10-18: "instead of dynamic sim lets take a page out of the ALIVE mods book and actually virtualize")

Inspired by ALiVE's profiles; our own build for Contractor's zones (docs/virtualization.md).

#### Added
- **Far groups become profiles.** An enemy group far from every player and squadmate (700 m),
  calm and out of sight, leaves the world and becomes a few lines of data: who is in it, each man's
  kit, rounds, wounds, skill, orders and where it is going. It comes back as the same men, exactly
  as they were, once someone is within 550 m, and never where a player can see them come out
  (inside 300 m it comes back regardless). Patrols, hunter teams, the HQ's pairs, QRF waves, the
  high command's task forces and probes, and faction skirmish teams all do this.
- **Profiles keep doing their job.** A profile walks its route at its pace: faster on roads, slower
  up hills. When the enemy's command sends it somewhere new, it goes there.
- **Off-screen fights.** Two profiles of sides at war that meet fight it out in rounds. Men die or
  are wounded, a beaten side breaks off, and the dead lie where they fell with their kit on.
- **Garrisons sleep with their sites.** A garrison goes virtual at its posts once its site streams
  out, and comes back at the same posts when the site streams in. Its gun and mortar teams wait
  for it. The site still counts as held, answers its radio check-ins and keeps its officers.
- **Bigger hot zones.** A hot zone now also fields two roaming teams of four on every patrol route.
  They are the zone's standing force and are not counted in the budget that paces what is sent at
  the squad. Far from the squad they are profiles and cost next to nothing.
- **Vehicles and convoys too.** An enemy QRF or patrol riding a technical, and a mission's convoy,
  go virtual with their vehicles when everyone is aboard and they're far from the squad. The profile
  drives on at the vehicle's speed, slower off roads and up hills. It comes back as the same
  vehicles (damage, fuel, cargo) with every man in his own seat, and drives on. A QRF technical that
  gets where it was going off-screen is left parked there, and its men walk on. A virtual convoy
  that reaches the end of its route gets away, as a real one does.
- **Saved with the zone.** Every group is saved, virtual or not. A squad that leaves a zone and
  comes back meets the same men where they had got to. A zone left long enough for its loose gear
  to fade gets a fresh enemy instead.
- Tests: a `virtualization` suite (round trips, rules, movement, fights, never in view, counting,
  garrisons, saves, capacity) in CI, a co-op check in `net`, and `tests/virtualization_perf.gd` for
  timing. On the 4 km hot zone, 120 enemies with virtualization ran at 7.0 ms a frame (worst 15 ms).
  Today's 40 without it ran at 7.3 ms (worst 20 ms). 120 without it ran at 9.0 ms (worst 33 ms).

#### Changed
- Dynamic simulation (far AI asleep) stays only for the AI that isn't virtualized: vehicle crews,
  bombers, the rival PMC team and scenario waves.
- In co-op, clients are never sent anything about a profile. Its men replicate like any AI once
  they are back in the world, late joiners included.
### AI driving part 2 (Captain, 2026-10-19: "the squad's AI drives the squad's vehicles"; 2026-10-20 major batch)

The squad's AI drivers now drive as a column, carry the squad to a point and get it out short of
it, judge contact by the threat and their armour, and get themselves unstuck. Numbers are
Proposed.

#### Added
- **Columns.** "Follow me in vehicles" and any drive order with more than one vehicle form a
  column (`ConvoyColumn`):
  - each vehicle follows the lead's own trail, round the same corners and down the same road;
  - they keep 22 m apart by speed, catching up or holding back, and stop when too close;
  - an AI lead drives at 40 km/h and crawls while someone behind is straggling;
  - the lead can be the player at the wheel, an AI-driven vehicle or the player on foot.
- **Carry us there.** The squad mounts up (`Mount up`: a rifleman at each empty wheel, the
  autorifleman or grenadier on each free gun, the rest in the seats, a seat kept for each player
  on foot). Then:
  - the vehicles drive there as a column;
  - the passengers get out 100 m short along the way, further back while a known enemy is
    within 150 m;
  - they follow the commander if he rode along or is near, else they hold there;
  - drivers and gunners stay with the vehicles.
  If the commander is driving himself, the column follows him instead.
- **Contact while driving** (`DriveContact`), judged by the known enemies near the vehicle, the
  hits it just took, anti-armour (a launcher seen, a shaped-charge or blast hit) and the vehicle's
  armour class:
  - **Drive through**: an ambush within 50 m, or fire its armour shrugs off. It goes faster and
    the gunner fires on.
  - **Stop and dismount**: anti-armour, unless it's a tank, or more fire than its armour takes.
    The passengers get out on the side away from the enemy; the driver and gunner stay, and the
    gun keeps firing. The whole column halts with it.
  - **Abandon**: engine or wheels gone, burning, or the hull nearly through. Everyone gets out,
    crew too, to cover.
  Mount > "On contact" toggles judging off (always drive through).
- **Orders.** Command menu Mount: 5 Mount up, 6 Drive (by road, cross-country, carry us there,
  follow me in vehicles, come pick us up, stop), 7 On contact. Map: "Our drivers: drive here
  cross-country" and "Squad: mount up and carry us here".

#### Changed
- **Getting unstuck** (`VehicleAI`, every AI driver):
  - a wall or wreck dead ahead for 3 s (anything else for 10 s), or stuck twice at one spot: it
    backs off and goes round by a detour on the clearer side, wider each try;
  - the squad's drivers give up after 4 tries, plan the way again (by road, then
    cross-country), and report "stuck" (a carry gets out there).
- **AI drivers slow for corners ahead** (up to 40 m), not only once they're in them.
- **Command menu Mount** now has a Drive submenu (the drive orders moved under 6).

### Footsteps (Captain, 2026-10-20: "the current ones are terribleee", then "too much like minecraft, too heavy, need running, walking, slow walking, crouching sounds")

#### Changed
- **A sound per pace.** Footsteps now have their own sound for each pace: sprinting, jogging,
  walking, a slow walk and crouching. Each comes in a soft-ground version (dirt, grass) and a
  hard-floor version (concrete, wood, metal), so 10 sounds with 8 variations each.
- **Lighter.** No deep thud any more:
  - a light heel tick and a heel-to-toe roll;
  - the ground's fine grit, or a crisp tap on hard floors;
  - a scuff, which becomes a skid at a sprint, plus a little kit jingle when sprinting;
  - crouching is a muffled shuffle with cloth rustle.
  Each step slower is quieter.
- **New generator layers.** The sound generator has new layers (thumps, grains, rustle) and a
  per-sound variation count, so other sounds can use them too.
### Weapon detail pass (Captain, 2026-10-20: "we need to do a weapon detail pass soon")

The parts the reloads work are now on the models, they move in first person, and each reload
beat has its own sound.

#### Added
- **Model details, per weapon:**
  - M4, M27, HK416, C8: ejection port with the bolt carrier in it and the dust cover swung open
    below it. Also the brass deflector, forward assist, T charging handle, bolt catch paddle,
    magazine release and safety.
  - AK family (AKM, AK-74, RPK, SVD): ejection port, carrier and charging handle, the long
    safety lever, magazine release paddle and dust cover latch button.
  - L85A2: the cocking handle now rides in a cut slot, and the bolt carrier shows in the
    ejection port. Before, the port was too thin to show.
  - PKM, M240B, M249: a feed cover hinged at its front, with its latch (and its rail on the
    M240 and M249). A feed tray under the cover, a brass belt with links from the box onto the
    tray, and a charging handle on the right.
  - Mosin: the bolt handle and ball knob now sit above the stock line (the old ones were half
    inside the wood).
  - Springfield: the bolt in an ejection port, its shroud, handle and tactical knob.
  - M17 pistol: slide serrations and a slide stop lever.
- **Moving parts in first person**, split from the weapon and tagged like the magazine:
  - AR family: the carrier is locked back on an empty reload and slams home when the catch is
    slapped.
  - L85: the handle and carrier run forward when the release is pressed.
  - AK: the carrier and handle rack back and spring home.
  - Belt-feds: the handle is charged on an empty reload. The cover flips up while the box is
    changed and slams down at the end. The belt comes off with the box.
  - Bolt-actions: the handle turns up, the bolt draws back, then goes forward and down.
  - Pistol: the slide is locked back on empty and goes home.
- **A sound for each reload beat**, all generated (data/sounds.json `reload_*`): magazine out,
  magazine in, bolt back, bolt forward, cover open, cover close, belt laid, clip stripped. They
  replace the single "reload" sound that played at the start.
- **Third person follows the same keys.** When a reload begins, the host tells every peer the
  weapon, whether it's empty and how long it takes. Each peer then times it on its own clock:
  - the support hand goes from part to part and to the pouch;
  - the held weapon is drawn without its magazine while the magazines move: out, carried,
    dropped and in;
  - the beat sounds play there too. A player's own reload starts at the key press, not after a
    round trip to the host.

- **The pistol's magazine is its own part** (Captain: "pistola needs a sep mag too"). It sits
  in a well up the grip and drops out the bottom on a reload; a new one goes up in its place.
  Its floorplate is the grip's bottom.

#### Changed
- **The PKM rebuilt to the real gun** (Captain: "realistic pk please"). The old one had the
  box on the left, a wooden handguard and a perforated barrel jacket. Now:
  - the 100-round box hangs under the receiver's right side, and the belt feeds in from the
    right;
  - the ejection port and its flap are on the left;
  - a bare fluted barrel with a slotted flash hider;
  - the gas cylinder under the barrel, with the bipod on the gas block, legs folded back;
  - the carry handle folded down along the barrel.
- **Full-length magazines.** Real magazines didn't fit the 26 cm weapon frame, so every rifle
  but the WG-50 now has 6 cm more frame below (`RIFLE_BELOW`). Every point read off a rifle
  follows the change, so the weapon sits in the hands and at the eye as before.
  - AR family: the 30-round magazine is 18.5 cm overall, 12.5 cm below a 6 cm-deep well. The
    pistol grip is 10 cm, like an A2's.
  - AK: the banana hangs 17 cm under the receiver.
  - L85: 11 cm under the housing, at its real depth front to back.
  - M240 and M249 boxes are real size, and the M249 box's bottom now comes off with it.
  - Each magazine goes up into a real well, so the well shows open while it's out.
- **HK416:** the piston rod no longer rides on top of the rail; the real one is hidden. It now
  has a chunky free-floated quad rail over the gas block and a deep E2-style stock with its
  storage tubes.
- **Optics on the M240 and M249** ride the feed cover's rail and lift with it, as on the real
  guns.
- **C8 proportions:** it now has its real 15.7 in heavy barrel (longer than the M4's) ahead of
  a carbine-length handguard and an M4-length upper. Before, the upper ran 37 cm, half as long
  again as a real one.
- **reload_points** now gives each hand target on its new part: the AR's T-handle and catch
  paddle, the AK's knob, the belt-feds' right-side handles (the M249's was on the left) and the
  covers. They also account for a suppressor's length.

### Reloads reworked, and the L85's (Captain, 2026-10-20: "reload anims also need work")

References he named: Sicario's AR reloads, AK and AR reloads, common media (Heat, Modern Warfare
2019, Tarkov), and "make sure our L85 has a good reload and look too".

#### Changed
- **The magazine comes out.** It's now its own part in first person: the hand strips it out and
  stows it (tactical), or it falls free (empty). A fresh one comes up from the pouch.
- **Shared by every reload:** the weapon tips in so you glance at the well as the new magazine
  goes in, which is seated with a bump and given a tug. The weapon comes back up with a small
  overshoot.
- **Per family, in first person:**
  - AR: an empty reload ends with a slap on the bolt catch.
  - AK: the magazine rocks out and rocks in. An empty reload strips the old magazine with the
    new one, then racks the handle from underneath.
  - L85: it comes out of the shoulder and the hand reaches back under to the magazine behind
    the grip. An empty reload presses the bolt release, then taps the cocking handle forward.
  - Belt-feds: the gun is charged when empty, the cover opened, the box swapped, the belt laid
    and the cover slammed shut.
  - Bolt-actions and pistols also have their own reloads.
- **Empty reloads take longer**, because the bolt is worked: AR +0.3 s, AK and L85 +0.5 s,
  belt-fed +0.5 s, pistol +0.2 s. A weapon can set its own "reload_empty_s". AI squadmates take
  the same time.
- **Third person:** the support hand now works the weapon's real magazine, behind the grip on
  the L85.
- **The L85A2 model:** a magazine housing lip, the magazine release, the bolt release plunger,
  the right-side cocking handle and its slot, an ejection port and the cross-bolt safety. The
  handguard now runs back under the support hand, which now holds the handguard.

### Movement feel pass (Captain, 2026-10-20: floaty/slidey, camera, speeds, clunky actions; Star Citizen as the target)

#### Changed
- Paces for a man in kit: jog 3.6 m/s (was 4.0), sprint 6.0 (6.5), crouched 1.7 (2.0), prone
  0.7 (0.8), aimed half pace (was x0.6). Starts take 0.4 s to a jog and stops 0.28 s (were 0.3
  and 0.2), so moving has some weight without sliding.
- Jumps are a 0.6 m hop (were 0.9 m) with much less steering in the air.
- Going prone takes 0.7 s and getting up 0.9 s for players, slowed meanwhile. The view eases
  between stances instead of moving at a flat rate, and leaning rolls the view less.
- The view has weight: a dip on each footfall, a dip on landing that grows with the fall, a
  small nod when you set off or stop, a slightly wider view at a sprint, and the weapon trails
  your mouse a little (much less aimed). Turning head bob off in Settings turns these off too.

#### Added
- Walk: P toggles a walk (half pace) and back to the jog. Sprint still sprints. Rebindable.
### Loot rotation and a real rarity spread (Captain, 2026-10-20)

#### Added
- 72 new items, all priced, described and given a use: 13 guns (M16A4, Colt Canada C7A2, AKS-74U,
  AK-74M, RPK-74, Type 56, Zastava M70, AK-103, PKP Pecheneg, SVD-S, Glock 17, SIG P226, M1911A1)
  with .45 ACP magazines and rounds; 8 optics (Aimpoint T-2 and CompM4, EOTech EXPS3, ACOG TA31,
  Elcan Specter DR, Razor HD 1-10x, Leupold Mark 5HD, Schmidt & Bender PM II); 5 attachments
  (angled foregrip, M600 light, PEQ-15, 5.56 and 7.62 suppressors); carriers (Crye JPC and AVS),
  helmets (PASGT, MICH, FAST), plates (AR500 steel, PE medium, ESAPI), 3 packs and 3 pouches;
  5 grenades (RGD-5, F-1, M67, RDG-2 smoke, multi-bang); valuables (cash roll, euros, cash brick,
  watch, gold coins, rough gems, silver) and contraband (hashish, heroin, tramadol); 11 intel
  items (sat phone, SIM bag, hard drive, marked map, codebook, frequency list, tablet, drone
  controller, SD card, passports, written orders); 4 salvage items (copper wire, filters, solar
  panel, truck tyre).
- Item rarity: every item has `stats.rarity` (common, uncommon, rare, very_rare), the commonest
  tier it turns up in, ready for the tooltip to colour.

#### Changed
- Loot rotation: the Western rifles and pistols, nearly every optic and attachment, carriers,
  plates, helmets, packs, pouches, night vision gen 2 and 3, coloured smokes, breaching charges,
  knives and 19 medical items that never appeared anywhere now turn up in the tables. An HQ's
  weapons cache has its own table (Western rifles, optics, night vision, most of the very rare
  prizes); barracks hold personal kit; medical chests carry the full range of drugs, fluids and
  surgery kits.
- Rarity: every table's tiers are deeper (common boxes hold 2-3 things or a bundle, very rare
  holds real prizes: cash bricks, gems, gold, a sat phone with a codebook, a suppressed HK416).
  Cash and cheap intel are common, the $1,400 cash bundle is uncommon, jewellery and contraband
  rare. Very rare weights rise a little at hot-zone sites (HQ 4 to 5, QRF 3 to 4, compound 2.5 to 3.5).
- Dead drops, hidden caches and the HQ strongbox roll a rarity tier too (pools in
  loot_tables.json), instead of picking from fixed lists. A strongbox's valuables now vary from
  a modest stack to a real prize; it still always holds one contraband and one intel item.

#### Fixed
- The shop sold cash bundles, gold bars, jewellery and relics (they were missing from
  not_for_sale); valuables and contraband are found, never bought.
### The theatre map and the map screens in the shared look (Captain, 2026-10-20)

#### Added
- A theatre (world) map. Open it with World or Tab on the map (M), or with Theatre map over the
  ops desk's region map. Every zone is drawn as its own shaped area: neighbours share a border,
  region borders are drawn heavier, and the sea and the LHD lie to the west. Each zone is filled
  in the colour of whoever controls it: the company blue, allies green, Black Ridge militia
  orange, hostile armies red, neutral grey, and hatched when contested. Badges mark hot zones,
  contracts held and offered, a skirmish going on now, the enemy's alert while you're there,
  fights there this week, and flashpoints. The squad's zone is ringed, home (the FOB, or the
  LHD) is marked, links show their crossings, and each region's name gives its travel days from
  home. Hover a zone for who holds it, the threat, the contracts, recent fights and the rebel
  support tier there; the side panel shows the same for the picked zone, plus the legend.
  Pan and zoom with the mouse, keys (arrows move between zones, WASD pans, + and - zoom, F fits)
  or pad (d-pad and left stick, right stick pans, shoulders zoom).
- Zone control (`scripts/campaign/zone_control.gd`): who holds each zone, read-only for now.
  The base is the company's, a hot zone its faction-war holder's, any other zone the target of
  a contract there, else Black Ridge. A "zone_control" campaign section (synced to clients)
  overrides it and holds the home, for the zone-flip work to write.
- Closed contracts remember their zone, so the map can show where the fights were.

#### Changed
- The map screen (M) is in the shared look. Its bar wraps onto a second line in a small
  window, and a "?" button opens its controls (now including Tab for the theatre map).
- The briefing and extraction panels on the map use the shared text styles: 16 px body, 14 px
  notes and section heads, nothing smaller and nothing faded. Map labels and the ops desk's
  region map are 14 px or more, and the region map shows each zone's controller colour.
- The UI fit checks cover the zone map, the theatre map, and the briefing and extraction panels
  at all 10 window sizes and 4 UI scales.
### The LHD is home until you take a zone for the FOB (Captain, 2026-10-20)

Design: docs/lhd_home.md (the Captain's calls, and the Proposed ones for him to confirm).

#### Added
- A new campaign starts aboard the LHD, a ship you can walk around. The hangar deck holds the
  armory with the stash on its floor, the shop and supply cage, the muster line, and the vehicle
  park with the motor pool's vehicles parked in it. The medbay and the hiring office are their own
  compartments. Two stairways lead up to the flight deck, where helicopters stand on their spots
  and the ops room is in the island: deploy from there. Squadmates have a navmesh on both decks
  and the stairs. Clients join aboard like at the FOB.
- Taking a zone. A zone flips to the company once every HQ and QRF base in it has been taken out,
  counted across deployments (today, the hot zones). While home is the LHD, the client's liaison
  calls: the LHD's charter is running out and the client wants the company ashore. A
  seize-and-hold contract for that zone goes on the board: take the zone's HQ, then hold it
  through the counterattack. Lose it or let it lapse and it comes back the next day.
- Winning it makes that zone the FOB: home moves ashore to the base zone, built on that zone's
  ground. The stash, roster and motor pool move with the company, and the base takes that zone's
  place on the region map. The LHD stays offshore as the coast's support origin.
- A new test suite, lhd_home.

#### Changed
- While home is the LHD, the region map has no base cell, so no zone has a crossing "To FOB".
  The ops desk sells no defences aboard; they come with a FOB.
- Campaigns saved before this keep their FOB and play as before.

#### Fixed
- The contract board no longer offers jobs in a zone the company holds: not in the zone its FOB
  stands in, and not in a flipped zone while its seize-and-hold contract is out.
### A modern UI: new font, cleaner look, layout tools and explanations (Captain, 2026-10-20)

#### Added
- A UI font: Inter (SIL Open Font License, `fonts/OFL.txt`), in place of Godot's default. Body
  text is medium weight; headings, buttons and the HUD are semibold; titles are bold.
- Every menu explains itself. Each screen has a one-line subtitle saying what it's for, and a
  "?" button that opens how it works and its keys: main menu, pause, settings, inventory, loot,
  loadouts, medical (? or F1), shop, contract board, debrief, bug report and the base screen
  (each base page also has a line saying what it's for, and so does each terminal's ring entry).
  Buttons, settings, negotiation fields and lists have tooltips in plain words.
- Search, kind filter and sort in the inventory, the loot window and the loadout stash. They
  change only what's shown and in what order, never how anything is packed.
- Loadouts: each row shows the item's picture and its full description on hover. Drag a stash row
  onto the Kit column to put it on (as Wear, Mount or +1 would), or a kit row onto the Stash
  column to put it back.
- HUD layout: a new Settings tab with a size and an opacity for each part of the HUD (objectives,
  compass, squad list and command menu, radio and vehicle, weapon and armour, wound silhouette,
  objective markers) and a "Reset HUD layout" button. A bigger part keeps its corner of the
  screen.
- Medical menu: the arrow keys pick the body part (Left/Right) and the treatment (Up/Down), and
  Enter uses it. Rows are bigger and easier to hit.
- Command menu: the highlighted row has a background and an accent bar. With the mouse free, rows
  light up on hover and can be clicked. A footer lists the keys on tall enough windows.
- Item names in tooltips and the inspect panel are coloured by rarity (common, uncommon, rare,
  very rare), with the word in the stats line, for items that carry one (the loot work adds it).
- The ui suite checks that every menu screen has a subtitle, and that its open help still fits at
  1280x720 and a 2.0 UI scale. It also checks that the HUD layout at its biggest still fits, and
  that the reset puts it back.

#### Changed
- The theme is written by `tools/gen_ui_theme.py` from one palette (edit the script, not the
  .tres). It is cleaner: soft panel shadows, rounded corners, clearer hover, pressed and focus
  states, an amber main-action button and a red-edged one for actions that can't be undone, and
  restyled tabs, lists, pop-up menus, sliders, scroll bars, tooltips and key chips.
- Selling asks first. That covers the loadout stash's Sell, the base shop's Sell all, and Reset
  everything to defaults in Settings.
- The HUD's text is the size UiKit always said it was: 20 px, 16 px for its small lines, and
  28 px for the downed and killed titles. The theme had 18, 14 and 26. On short windows (1280x720
  at a 1.5 Menu and HUD size and up) the prompt, radio and vehicle lines drop to the small size
  so they still fit.
- Easier to read over the 3D view. The compass letters are 16 px, outlined, with brighter ticks.
  The ammo and armour lines are 16 px at 88% instead of 14 px at 70%. Objective markers are drawn
  at 95% near and 75% far (they were 70% and 45%), with outlined 16 px labels. The objectives list
  is outlined. The wound silhouette is about a third bigger.
- The item tooltips and inspect panel (ItemInfo), the armour readout and the medical menu use the
  shared palette instead of their own colours.

### Binoculars and the legs-still fix (Captain, 2026-10-20)

#### Added
- Binoculars you can look through. Press B on foot to raise them: a 7x view with a two-circle
  frame and a mil scale, and the weapon lowered. Press B again, sprint, or press a weapon key to
  lower them. You walk slowly and can't fire while they're up. Seated, B is still the vehicle
  view. The key can be rebound in Settings.
- Auto-walk: press = to walk forward hands-free. Sprint still sprints and A/D still steer. W, S
  or = again stops it, and so does going down or getting in a vehicle. Rebindable, and on the
  pad wheel.

#### Fixed
- AI no longer slide with their legs still at high frame rates. The model measured speed over
  one drawn frame, but bodies move on 60 Hz physics ticks. Above 60 fps, a jog read as standing
  still on frames with no tick, and as a teleport (zeroed) on frames with one. Speed is now
  measured over the time since the body last moved.
- F-07 (dynamic sim): a body only falls asleep when it isn't moving up or down. It no longer
  also has to report touching the floor, so patrols far away fall asleep again.
### World visual pass: buildings, compounds, the AA gun, props, the ground, tree and bush hitboxes (cghath's side)

#### Changed
- Generated buildings each get their own wall colour from a small palette for their style
  (rendered block in cream, ochre, pale blue, green or pink; three brick and stone shades; four
  mud shades, some lime-washed) and a skin: window and door frames and sills, a dark plinth,
  rising damp, eaves over sheet-metal and tiled roofs, a cornice on concrete ones, roof beam ends
  and wooden lintels on mud brick, corner stones on brick and stone, shutters on some, signs over
  shops, police stations and clinics (a red cross), copings on parapets and yard walls, and water
  tanks and vents on roofs nobody goes up to.
- Hand-built modules are dressed from their own boxes: a bag pattern on every sandbag wall, frames
  and soil on HESCO, plinths and copings on walls, a gable on tents, crates and fuel drums with
  bands, and the compound gets pillars along its wall and a gate (posts, a beam overhead and
  steel leaves opened back against the wall).
- The AA emplacement's gun is olive with its barrels raised over the bags, magazines, jacketed
  barrels and muzzle brakes, and ammo boxes in the pit.
- Pads under modules are no longer one flat square of earth: gravel and trodden patches, and
  dry grass worn in round the edge.
- Roadside props are crate stacks, painted drums or debris piles; ruins are broken wall corners,
  rubble mounds or car wrecks. A prop on a slope sits down into it.
- The skin is new colour variants of the materials walls already are
  (`VoxelWorld.VARIANT_OF`): they take rounds and blasts exactly as before. It is stamped after
  the structure and kept out of navigation (`ZoneModules.skin`, `VoxelWorld.add_box_m(..., skin)`),
  so cover, navmeshes, garrison posts and loot spots are unchanged.

#### Fixed
- Tree trunks collide as the trunk is drawn (an octagonal frustum), not as a thinner cylinder:
  rounds through the octagon's corners went through the trunk.
- Rocks and props collide as drawn. They were a box 0.9 of their size, and turned ones were drawn
  sheared, off their own collision.
- Conifers hid people up by their tip and out past their skirt. Their sight cylinder is now
  narrower and lower (`ZoneScatter.CONIFER_R`, `CONIFER_HIGH`).
- Scrub and thickets filled about two thirds of the cylinder they hide people in. Their clumps now
  fill it.
- New checks: the forest suite's hitbox checks and the squad suite's conifer lines.
  `tests/world_shots.tscn` takes the look's screenshots.
### Picture-in-picture scopes (art task; cghath's side)

#### Changed
- A magnified optic (the 4x prism, the LPVO, the DMR scopes, the holo's magnifier when it's up)
  shows its own picture in the lens at exactly the optic's power. The rest of the view stays at
  normal width around it, and the black ring stays. The picture looks where the shot goes, so
  aim sway, breathing and recoil move it. The gun's own kick and settle move the lens across the
  screen. Red dots and holographic sights at 1x are unchanged.
- Under NVG the scope picture is green and grainy like the rest of the goggles' view.
- The picture renders only while you're aimed through a magnified optic. It uses the level's
  world, a size set by the lens on screen and the render scale, cheap anti-aliasing, and is off
  on a weapon switch, when down or dead, in a vehicle seat and on headless runs.

#### Added
- Video setting "Scope picture-in-picture": Off (the old full-screen zoom behind the ring), Low,
  Medium (default) or Full resolution.
- `tests/pip_shots.tscn`: screenshots of the prism and the 3.5-10x by day, at dusk and through
  NVG, with each picture's render cost. The attachments suite checks when PiP is on and at what
  power.

#### Fixed
- A tube optic in a fire-from-vehicle seat now shows its glass and reticle. It used to zoom the
  whole view with no reticle.
### The tutorial, round 2: the complex parts, and skipping what a teammate teaches (cghath, 2026-10-20)

#### Added

- **New tutorial sections and steps**, each ticked off by what the game sees you do:
  **Gear** (hang a spare pouch on your carrier through MOLLE, mount a weapon light on your
  rifle, switch it on with L; what Mass means), **Squad orders** (send the squad somewhere,
  bring it back to formation, pick a formation), **Casualties** (a villager down with an open
  artery: drag him out of the open, let go, put a tourniquet on him; what going down and giving
  up mean), finer stances (Caps Lock) under Moving, and **The campaign** (short steps to read:
  the contract board, loadouts and buying missing kit, the briefing, extraction, the debrief).
- **A section list** (Page Up, and open when the tutorial starts): tick a section "Skip: a
  teammate teaches it" and the tutorial jumps past it; Start here goes to any section. The ticks
  are kept until you quit the game. **Shift + Page Down** skips the rest of the current section;
  Page Down still skips one step. The tutorial is the host's: whoever hosts it is the learner and
  has the list and the keys.
- `tutorial` test: the new steps, the section list, skipping a section and the kept ticks. `ui`
  test: the tutorial's panel and its section list fit at every window size.

#### Changed

- The tutorial's panel uses the shared UI look and moves up to fit a short window.
- "Gear and orders" is split into **Gear** and **Squad orders**.
### Base assault during a debrief's days: warn, then resolve (cghath's call on audit A2-04)

#### Changed
- When the days a contract's debrief is about to pass include the day a booked base assault
  falls due, the debrief warns first ("Base assault expected on day N ..., before you're back")
  and the host chooses. **Head home first:** the deployment ends and the assault meets the squad
  at the FOB, live. **Carry on:** the days pass with the squad out, and the assault is met
  without them, as before. Pay, salvage, the days and their costs are the same either way. Clients
  see the warning and the host's choice. The host can't close the debrief or save until it
  chooses. With no assault due in those days, nothing changes.

#### Fixed
- Calling a helicopter or allied troops in an inland zone after a coastal one no longer logs a
  script error. The coastal zone's LHD deck was freed, and `Supports.origin_for` assigned it to a
  typed variable. Found by the new trips in `base_zone_test`.

### Executive audit of 2026-10-19: ten findings fixed, three logged for Claude's side (cghath's side)

The audit is in `docs/audits/executive-2026-10-19/` (README, PART-1, PART-2). The repairs are in `FIXES.md`.

#### Fixed
- A2-01: a raid (by air or through a crossing) no longer picks up a job prepared for another
  zone. The job stays accepted and prepared for later.
- A2-02: saving during a deployment keeps the helicopters lost and their cooldowns, so a lost
  helicopter no longer comes back after a reload, and an expired cooldown doesn't return.
- A2-03: recon, hold, convoy, rescue and escort objectives carry on where they were after
  leaving and coming back to their zone or reloading a save. They no longer sit "active" for good
  with nothing running them. Their crews, waves, wrecks and convoy vehicles return once each, by
  their saved ids (`ScenarioCheckpoint`).
- A2-04: the days a debrief or a board wait passes now book base assaults and turn the rebel
  week too, as the base's own day advance always did. Several weeks at once each count.
- A2-05: the second fighter upgrade sends ten fighters, as paid for (6/8/10; 4/5/6 in a hot zone).
- A2-06: rebel fighters who follow the squad across a crossing stay rebels, and as many come over
  as were still up.
- A2-07: a raid banks the loot set down in the LZ, the holds and the gear on bodies carried out,
  and takes them out of the zone, as a contract does.
- A2-08: arriving in a remembered zone after travel keeps the travel time; a resumed save still
  keeps its own.
- A2-09: taking over a casualty's HX-1 while wearing an LX-3 is refused ("Take off your exo frame
  first") instead of deleting the HX-1.
- A2-13: the aim slowdown assist ignores civilians, captives and enemies behind walls.

A2-10, A2-11 and A2-12 are in Claude's files (the squad AI and vehicles). They are logged as F-04
to F-06 in `docs/audits/followups.md`, with a ready fix on branch `fix/a2-ai-vehicles`.

### Compound loot (cghath's side, 2026-10-20)

#### Added

- **Loot boxes by rarity, in the rooms where they'd be** (`data/loot_tables.json`,
  `WorldValuables`): every enemy site has box spots by room: an HQ's office desk and radio room,
  a compound's command-building desk, armory crate, footlockers, store shed and container, an
  outpost's bunker and ammo crates, a checkpoint's seized goods, village cupboards. The fitting
  rooms always get one, a few of the rest are picked per site. Each box rolls common, uncommon,
  rare or very rare by its site's stated weights (rare and very rare together 6% at a village
  up to 17% at an HQ), then a bundle from its table; very rare only in hot zones. The same zone
  rolls the same loot every visit.
- New `loot` test suite (local default list and CI).

#### Changed

- **Looted boxes stay looted:** caches and site boxes are saved with the zone (what's in them,
  and whether a strongbox was opened) instead of restocking on every reload.
- Site boxes replace the old "one piece of cash or intel, 18% something better" roll and the
  contraband swap; the HQ strongbox is unchanged.

### The tutorial, finished (cghath, 2026-10-20)

#### Added

- **New tutorial sections**, each step ticked off by what the game sees you do: **Medical** (a
  graze to bandage yourself, then a second one: call "Medic!" or "Treat me" from the command menu
  and a squadmate patches you up), **Tagging enemies** (Y, by radio), **Vehicles** (get in as
  driver, drive, take the gun seat, order the squad in, everyone out), **Rebel support** (ask a
  villager for work, give him supplies, Support > Rebels > Lookouts) and **Static guns** (pick up
  one of the M2's two loads, set it up, pack it up; shown once the game has static guns).
- Steps are grouped in sections, named in the panel's title.
- `tutorial` test suite: the tutorial as the menu starts it, every new step driven to the end.

#### Changed

- The tutorial's compound: its hostile patrol goes and the squad holds fire, so nobody fights
  while you learn; the target stands in the open yard (it stood inside the main building); an
  M-ATV, a villager and the static gun's loads wait south of the gate; the kit has two loose
  bandages.
- In the tutorial a villager answers "Ask if they need help" and "Give supplies", and the
  rebels' Lookouts answer the call, without a campaign.

### IFF marks you can read through a scope (Captain's tasking 7, 2026-10-19)

#### Changed

- **Armbands and helmet marks now show at combat range**: before, they disappeared past 45 m.
  They're now bigger blocks of flat colour (an armband over most of each upper arm, a band round
  the helmet plus a crown square, or a band round the head with no helmet) that glow slightly at
  dusk and are drawn out to 400 m. Blue is the company, green is allies (allied troops and
  rebels on our side), orange is the Black Ridge militia, and red is every other hostile.
  Civilians and HVTs have none. A body keeps its marks, and its ragdoll carries them. All the
  art is in `GearRig.iff_art`.
- **Under NVG, friend and foe look different**: friendly marks are IR-reflective and flare in the
  tube, while enemy marks are plain cloth and stay dark.

#### Fixed

- Eastern Concord troops in their Chinese kit wore militia orange (they share Black Ridge's
  urban camo). They now wear hostile red: every hostile's side is set when it spawns, from its
  camo and whose zone it is (`GearRig.hostile_tag`), and that travels with the spawn to every
  peer and into saved bodies.
- Faction skirmishers at odds with the company had no marks. Friendly rebels wore the company's
  blue.

### UI pass: debrief, salvage and the loadout menu (Captain's tasking, 2026-10-19, task 4)

- **Debrief and salvage** use the shared look: theme title, headings, figures and buttons, and
  no text under 14 px (the figure captions, table headers and footer were 12 to 13 px). A
  tagged pallet's or intel's buttons wrap under its line instead of running off a narrow panel;
  the salvage table's item column wraps and takes the room the numbers leave; claimed rows are
  green, rows that won't fit dimmed; casualties are listed one each, the dead in red.
- **Loadout menu** uses the shared look too. Nothing is clipped silently any more: the title,
  headings and status wrap; a person's button cuts with "..." and shows the whole line on hover;
  a drop-down is as wide as its prompt. It opens with the first person focused.
- **Base screen:** a squadmate's "HX-1: n/8 missions" no longer shrinks to nothing on the squad
  page. **Inventory:** an item's short name on a swatch is cut with "..." instead of breaking
  mid-word.
- **The `ui` suite checks harder**: at all 10 window sizes and 4 UI scales, every screen is
  checked for text under 14 px, text cut without "..." and a tooltip, squeezed text, controls
  outside what clips them, and overlapping controls. It now also fits a full debrief (salvage open
  and closed) and the loadout menu, and self-tests that each check still catches its problem.

### Economy balance proposal (cghath's side, 2026-10-20)

#### Added

- `docs/economy_proposal_2026-10-20.md`: measured economy balance numbers for the Captain to
  approve (contract pay, hot zones, intel, daily wages and upkeep, capped shock costs). Proposed
  only: no game number or code changed.
- `tools/economy_sim.tscn`: a headless economy simulation that plays short campaigns through the
  real board, debrief, bill and loot code with play profiles standing in for the fighting
  (`--runs`, `--days`, `--variant current|proposed|both`). Not a test suite; CI never runs it.
### CI flakes (cghath's side, 2026-10-20)

#### Fixed

- **Test flakes** that turned most CI runs red, each now waiting on what its check needs:
  world (the ground guard's own round no longer races the test's check; the fall spot is clear
  of rocks round the whole capsule; the far-AI sleep stays off while it checks the fall, since
  it froze the faller in his last metre: F-07 in `docs/audits/followups.md`), map (the staged
  squad stands still in the LZ before the extraction countdown), loop (the casualty lies out of
  the helicopter's own loading reach until the player carries him over), base_zone (the player
  is whole again before the fly-on, the crossing-on's wound having bled him out cold on a bad
  roll; confirming waits until the crossing counts him in), voice (asking waits until the
  crosshair finds the soldier, and nobody else stands on the line), casualty (looting from
  beside where the body lies, not its capsule).
- **A squadmate's slot no longer sits behind a wall from the lead for a moment** (casualty soak
  "stuck"): the 2 s hold that stops slots flipping by a doorway no longer keeps a slot (or a
  team's place) on the far side of a wall from the lead himself. Turning the corner by the
  compound's back wall, the second team's place and then Golf's slot sat outside it in turn,
  and he set off round by the gate.
- **Blood no longer falls through the ground under a body lying on it** (interaction, CI): a drop
  from the lowest skin, pressed a little into the ground, found no floor below it and lay as a
  pool cell 2.5 m under the yard; the floor is looked for again from just above it.
- **CI pinned to ubuntu-24.04** (both jobs): `ubuntu-latest` moves to Ubuntu 26 from
  2026-10-19, and the suites aren't proven there yet.

#### Added

- **A manual CI run can name its suites**: `gh workflow run tests.yml --ref <branch> -f
  suites="world map"` runs only those (space- or comma-separated); push and pull request runs
  still run every suite. `tools/check_ci_suites.sh` checks the workflow's list against the
  local default.

### Executive audit fixes and their review (cghath's side, 2026-10-17 to 18)

An outside audit of v0.4.36 (`docs/audits/executive-2026-10-17/REPORT.md`) found six defects;
all six are fixed (`FIXES.md`), then reviewed, and the review's problems fixed too.

#### Fixed

- **Killed garrisons stay dead after a reload** (E-01): bodies keep their post's spawn id, and a
  saved fallen-post ledger outlives corpse cleanup and extraction. Saves from before v0.4.10
  (callsign labels) migrate; v0.4.10 to v0.4.36 saves may duplicate a post once.
- **Cleanup never deletes the body a player stands beside** (E-02): it measures to where the body
  lies (`Soldier.body_point()`).
- **QRFs and hunters only spend the reserves they actually field** (E-03): the planned headcount is
  reserved, unspawned heads are returned, and short reserves are refused. A launch from two bases
  is approved once (one op, one radio order); later waves of it are paid silently. A shortage is
  still recorded, and a hunter with a stale last-known position still sends a probe.
- **A commander killed before command noticed him still leaves them headless** (E-04): HQ
  commanders register at spawn; death, cuffs, surrender or delivery all count.
- **Crow's Pass offers no contract from the enemy against itself** (E-05): Meridian is its client;
  the generator rejects hostile or unknown employers.
- **The draft-release helper can't touch a public release** (E-06): it reads the release state
  first and refuses public releases or unreadable state. Its test now enforces its "never upload
  or create" checks and can only reach an inert `gh` double.
- **One medic at a time walks in on a wounded HVT**: while one takes over from the escort, other
  medics leave it to him; if he goes down, another takes over.
- A packed massive neck wound can be clamped; a late joiner sees an already-held casualty in the
  held pose; an escort keeps caring for his HVT until a medic reaches the body; a bullet that
  wounds someone before a vehicle, armour or another body stops it reports the body hit.
- **CI**: the workflow is valid again (the runner job's log folder moved into its steps: GitHub
  doesn't allow `runner.temp` in a job's `env`); CI runs all 44 local suites, including voice,
  compass and audit_fixes, and a parity check fails if the lists differ.

#### Changed

- **Urban AI is cheaper**: building probes use a per-region index; building records are shared
  across scan heights (a building's answer no longer depends on which scan came first); zone
  navmesh chunks join by aligned vertices instead of proximity edges. A chunk baked from a
  module's stand-in is rebaked once the module's voxels are built. Town benchmark: average tick
  16.1 ms, p95 23.7 ms, building scans 58 ms a second (budgets 20 / 40 / 120; R0158).
- Helicopter clearance planning includes the tilted airframe and 2 m for contour lag (the 5 m
  clearance requirement is unchanged).
- Test fixtures: generated module variants, real body positions for reach, physical muzzles,
  seated-hitbox waits; the missions suite runs with the enemy commander on, except around the
  sections that drive the response by hand.
- The audit's probe scripts live outside the project (`Contractor-test-logs/audit-2026-10-17-probes/`);
  only its reports are in the repo.

#### Known gaps

- While a module is streamed out, a breach on a chunk seam can detour about 3 m until its voxels are
  rebuilt.
- Killed civilians and HVTs can still walk again after a reload when their body record was cleaned
  up (same cause as E-01, not yet fixed for people).
- On cghath's machine `map` (extraction countdown) and `ui` (vehicle readout) fail even on dev
  38f5825 (R0146); both pass on CI.
### Mission variety: sabotage done properly, every type played through (task 8, 2026-10-20)

#### Added
- **Sabotage hits what the enemy fights with**: a fuel store (the compound's generators and fuel
  drums; new steel drum stores at the HQ and the QRF base), a vehicle park (two or three technicals
  parked at an outpost, checkpoint, compound, QRF base or HQ) or the comms site's radio mast. A
  park counts once every vehicle burns, is a wreck or can't drive: a breaching charge set on each
  does it. Sabotage now comes up at checkpoints and compounds too, so contract zones get it.
- Tests: contracts checks the five mission-variety types on the board (in fitting zones, contract
  and hot); missions takes each from the board and plays it to the end through the real objective
  code (crews killed, crate carried out, position held, crew walked to the LZ, sites watched,
  charges set), plus a vehicle park left standing that pays nothing.

#### Fixed
- **The convoy's cargo bonus can be earned**: the crate is now a supply crate, and any one carried
  out counts. A crate carried in both hands kept no intel id, so the old hard case never counted.

### Day and night, weather: wave 7 S1 MVP (Captain, 2026-10-18)

#### Added
- Time of day per zone (`DayNight`, `scripts/world/day_night.gd`, a "DayNight" node in every
  level): a zone's `"hour"` (its data/missions.json entry or its definition; a deployed
  contract's own `"hour"` wins), 08:30 without one, passing at an hour per ten minutes in a
  contract zone (standing in the compound, the base and the range). The sun climbs and sets
  with it; at night a dim blue moon lights the level from the other side, and the sky (the
  procedural sky, or `zone_sky.gdshader` through its existing uniforms, no shader edit),
  ambient, fill and haze darken. A level at its own default keeps the look it built.
- Weather: `"weather"` the same way, one of clear, overcast, fog, rain, storm (`DayNight.WEATHER`,
  a row of data each): thicker Environment fog, a greyer, dimmer sky, darker nights, rain as
  GPU particles round the camera (not headless), slower spotting, a limit on how far anyone is
  seen (fog 150 m, storm 250 m, rain 400 m), footsteps carrying less in rain and storms.
- Darkness cuts AI spotting (`Spotting.sight_x`): `DayNight.darkness_at(pos)` (0 day .. 1 night)
  slows the spot up to 4x and hides anyone past the night's sight (60 m at full dark, 600 m at
  dusk) unless they fired in the last 1.5 s; one marked line is the hook for NVGs (wave 7 S2).
- Storms ground helicopters: `DayNight.grounds_aircraft()` answers `Supports.can_fly` through
  `CompoundLevel.weather_grounds_aircraft`, so the UH-60 supports refuse ("Helicopters are
  grounded: the weather won't let them fly") and a heli insertion goes on foot.
- Saved with the zone (`GameState.sky`, `"sky"` in the zone save; older saves have none) and
  replicated: a client asks the host when its level loads, the host sends it every 10 s.
- Dev keys (DevTools, the host): `;` moves the clock on 2 hours, `'` the next weather.
- `daynight` test suite (tests/daynight_test.gd), in tools/run_tests.sh and CI.
### NVGs, first slice (wave 7, S2; Captain: "Day and night, weather, and NVGs")

#### Added
- Night vision goggles by generation (`data/items.json` `nvg_gen1`/`nvg_gen2`/`nvg_gen3`,
  priced 3000/5500/9000 in `data/prices.json`): they mount on a worn helmet, and what's
  mounted lives in the helmet's item state (`"nvg": {"id", "lowered", "battery_h"}`), so it
  travels, saves and replicates with the helmet. Inventory: "Mount on <helmet>" on a carried
  NVG, "Remove <NVG>" on the helmet.
- The NVG key (`nvg_toggle`, U by default, rebindable; N is the next objective): flips the
  NVG down or up (`Soldier._server_toggle_nvg`, host-side); with none mounted it mounts the
  first one you carry and lowers it, and without a helmet it says to put one on.
- `Nvg` (`scripts/combat/nvg.gd`): `restores(viewer)` (0..1, the share of the darkness
  penalty to sight a lowered, powered NVG gives back; gen 1 0.6, gen 2 0.8, gen 3 0.9,
  Proposed), `is_lowered`, `is_on`, `fov_of`, battery helpers, host mount/remove/lower/drain.
  For day and night (S1) at integration: `dark *= 1.0 - Nvg.restores(viewer)` in spotting.
- Battery: drains in real hours of lowered use (6/10/14 h by generation, Proposed), charged by
  the host in 10 s steps; flat, the goggles stay down but show and restore nothing. Stowed, an
  NVG keeps its charge.
- `NvgView` (`scripts/combat/nvg_view.gd`): the wearer's own view through lowered, powered NVGs:
  green, brightened, with grain and a vignette, inside the tube's field of view (40/45/50 deg
  by generation, Proposed), the unaided eye's dim view around it.
- Test suite `nvg` (`tests/nvg_test.gd`), in `tools/run_tests.sh` and CI.
- With day and night (S1): lowered, powered NVGs give back their share of the dark's penalty
  to spotting (`Spotting.sight_x` scales darkness by `1 - Nvg.restores(observer)`).

#### Not yet
- No NVG model on the helmet (Captain's art side), no spare batteries or recharging, the NVG's
  mass isn't added to the helmet's, AI don't wear or use NVGs, IR illuminators and lasers
  later. A scope's picture isn't green through NVGs.
### Modular weapon attachments: grips, lights and lasers (wave 7 S3; Captain: "Modular weapon attachments")

#### Added
- Four attachments in `data/items.json` (type `attachment`, `stats.mount`, `stats.fits` = the
  weapon tags they fit; proposed prices in `data/prices.json`): Vertical Foregrip
  (`grip_vertical`, underbarrel, railed rifles, $250: x0.8 recoil, x0.85 aimed sway), Weapon
  Light (`light_weapon`, side, rifles and pistols, $350), Visible Laser (`laser_visible`, side,
  rifles and pistols, $450), IR Laser Aiming Module (`laser_ir`, side, rifles, $1100).
- `GunAttachments` (`scripts/combat/gun_attachments.gd`): the underbarrel and side mounts, next
  to the optic (`Optics`) and the muzzle (`Suppressors`), which keep their modules. What's on a
  gun lives in its item state (`state.underbarrel`, `state.side`, `state.side_on`), so it
  travels with the gun (stowed, dropped, looted, saved) and replicates with the inventory.
  `all_of(weapon, state)` gives every mount -> item id, optic and muzzle included. Host-side
  inventory actions `mount_attachment`, `remove_attachment` (target = the mount) and
  `toggle_attachment` (validated: the item is an attachment in your kit, the gun takes it);
  in the inventory: right-click it > Mount on <gun>; right-click the gun > Switch on/off,
  Remove. The mass and value of a gun include them.
- The weapon-light key, L (`Controls.KEYS weapon_light`, proposed): the light or laser on the
  gun in hand on or off. A light is a SpotLight3D along the aim, a visible laser a thin red beam
  to what it hits (`scripts/combat/gun_light_rig.gd`, placeholder look, drawn on every peer from
  the replicated state; no models on the gun yet). An IR laser draws only through night vision
  (`ir_seen`, the hook for the NVG work; nothing sets it yet).
- The AI spots a soldier with a light or visible laser on sooner (`Spotting.LIT` x0.4 with the
  beam towards it, `LIT_SIDE` x0.75 otherwise; proposed).
- Test suite `attachments` (in `tools/run_tests.sh` and CI): validation, the grip's kick and
  sway, mass and value, stowing and drawing, save/load and replication, the light and lasers,
  a suppressed shot, a 4x prism's zoom.
### Controller support and co-op assists (wave 7, S4; Captain: "Controller support and optional help for new co-op players")

#### Added
- On the pad wheel too: the NVG flip (U) and the weapon light or laser (L) from S2 and S3.
- A full gamepad layout (Xbox names; `Controls.JOY_BUTTONS`, `JOY_AXES`), next to the keys:
  move on the left stick, look on the right, RT fire, LT aim, A jump (the brake driving),
  B crouch, X reload, Y hold for the interaction menu (the right stick moves its cursor; click
  the right stick with Y held for yourself; downed, hold Y to give up), LB/RB lean, L3 sprint and
  hold breath, D-pad up primary, right sidearm, left grenade, down prone, Start pause.
- The pad wheel (`PadWheel`): hold View, point the right stick at a slice, let go: inventory,
  map, medical menu, quick treat, fire mode, launcher, rest weapon, inspect, optic zoom in/out,
  next objective, objectives list, vehicle view, get out, quick save. Stance adjust and
  push-to-talk orders stay keyboard-only for now.
- Right-stick look (`PlayerInput.update_pad`, `GameSettings.stick_look`): Controls tab rows for
  stick sensitivity, a round deadzone (15%), a response curve (1.6) and invert, saved in
  settings.cfg's new `gamepad` section; aiming, scopes, concussion and loaded sprinting slow it
  as they slow the mouse; seated, it turns the view as the mouse does.
- Co-op assists (`Assists` autoload), off by default and set by the host for the whole session
  (the Controls tab's "Co-op assists" rows, greyed out on a client; sent to every client and to
  late joiners; a client's request or anyone but the host's sync is refused):
  `aim_slowdown` (the stick turns at 40% over an enemy within 4 deg and 200 m; never the
  mouse) and `wound_hints` (a HUD line: your worst wound, where, what to use, whether you carry
  it). Objective markers were already on the HUD (the player's own setting), so they're not an
  assist.
- `controller` test suite (`tests/controller_test.gd`), in `tools/run_tests.sh` and CI.

### Squad roles and the Vantage Group rival PMC, first slice (Captain, 2026-10-17)

#### Added
- LX-3 presets (`data/roles.json` `lx3_capable`, `Roles.kit`/`apply_kit`'s new `lx3` argument):
  any existing role can be kitted with the LX-3 Assist Frame and Visor Helmet instead of the
  normal helmet without its stored role changing, so squad_ai.gd's role checks (`Roles.MEDIC`
  and so on) keep working. Not wired into AI auto-fill; a mission, loadout screen or roster hire
  opts a soldier into it deliberately, the same boundary `anti_tank` already draws.
- `heavy_gunner` (M240B) and `ammo_bearer` roles (`data/roles.json`): converted slots like
  `anti_tank`, not added to `fire_teams`. `SquadAI._maybe_resupply_gunner` hands the nearest
  belt-fed LMG carrier a box of whichever ammo his own weapon takes when he's run low and the
  bearer is already close (mirrors the medic-follow conventions near `MEDIC_FAR_M`, generalised
  by weapon tags (`lmg`, `belt`) rather than by role, so it serves Black Ridge's PKM gunner and
  any autorifleman's M249 too, not only Vantage's M240B — Captain, 2026-10-17, "the new roles go
  to the factions too"); it doesn't yet path to the gunner on its own. Black Ridge's own mix
  (`CompoundLevel.HOSTILE_MIX`) gained a PKM ammo bearer alongside its existing gunner, cast the
  same way (`hostile_role`, mirroring `rival_pmc_role`) at every spawn site (`EnemyResponse`,
  `Reinforcements`, `ZoneLevel`'s garrisons). A hostile cast as `heavy_gunner`/`ammo_bearer`
  skips the player-facing role kit (`CompoundLevel._make_soldier`): its own `hostile_loadout`/
  `rival_pmc_loadout` entry already carries the right gun and caliber, so re-kitting it would
  only stack a redundant weapon and the wrong ammo on top.
- `scar_h`, the SCAR-H battle rifle (`data/items.json`, `data/prices.json`): semi-automatic
  7.62x51, harder-hitting than the M4A1 with real recoil (`recoil_deg`). Renders through
  `VoxelArt.model_for`'s existing data-driven rifle model, no art-script changes. `ExoFrame`
  gained a `recoil_mult` (damps a working LX-3 wearer's recoil a little, read from
  `SoldierMovement.recoil_mult`) so the new recoil has somewhere to hook into instead of a
  parallel system; the heavy exo's own recoil interaction is left to its own branch.
- The Vantage Group, a rival PMC faction (`data/factions.json` `vantage_group`): fields modern
  gear (M4A1/SCAR-H riflemen, an M240B gunner and its ammo bearer) through
  `CompoundLevel.rival_pmc_loadout`/`PMC_MIX`, parallel to the Black Ridge militia's
  `hostile_loadout`. `EnemyResponse.enemy_faction`/`Reinforcements.enemy_faction` pick which
  mix a zone's patrols, hunters and reinforcement waves field; `ZoneLevel._on_contract_live`
  sets it from a live contract's `target`. Garrison spawns (`_spawn_queued_garrison`) and the
  tutorial compound's `HOSTILES` are left on the Black Ridge mix for this slice.
- Faction colours (Captain, 2026-10-17: "black for enemy pmc, tan for us"): new `VoxelArt` variants
  `black` (Vantage) and `tan` (the player faction), and Black Ridge's `urban` variant's patch
  colour changed from navy to orange ("give the militia we typically face early game an orange
  marker on their uniform instead of the same red one that's on the PMC"). Every friendly AI
  spawn site (`compound_level.gd`, `base_hub.gd`, `base_level.gd`, `aav_support.gd`,
  `heli_call.gd`) now spawns `tan` instead of `multicam`; Vantage's spawns (`enemy_response.gd`,
  `reinforcements.gd`) spawn `black` instead of `urban`. `Soldier.PLAYER_VARIANTS` gained `tan` too.
  Fixed in passing: the plain Ballistic/Bump/Heavy helmets never actually had the `faction_color`
  stat the LX-3 Visor Helmet already carried (`GearRig._rebuild`'s `set_cover`), so every
  faction's basic helmet rendered in one fixed colour regardless of variant; added it to all
  three (`data/items.json`) so helmets tint by side like the rest of the kit now does.
- Vantage's exo gear, gated by the contract's real 1-5 difficulty rating (`true_rating`, read in
  `ZoneLevel._on_contract_live`, not the briefing's `rated`, which can understate it): the LX-3
  Assist Frame and Visor Helmet from `PMC_LX3_DIFFICULTY` (4) on every PMC soldier but the exo
  pilot slot, which from `PMC_HX1_DIFFICULTY` (5) climbs straight into the HX-1 Assault Frame and
  its Walker Gun instead (`CompoundLevel.equip_hx1`, via `Inventory.put_on`/`unequip` — the same
  end state `ExoMech.server_enter`'s climb-in reaches, without playing out its 3.5 s animation,
  which a freshly spawned hostile has no reason to do; `ExoMech`/`ExoFrame` read the exo slot
  reactively, so piloting, size and pad armour all follow from the inventory state alone).
  Cutoffs (Captain, 2026-10-17, "Vantage gets exo suits and heavy exo suits but only on higher
  diffs"): LX-3 from a merely hard mission (a real but moderate edge); the HX-1 reserved for the
  single hardest tier, so it reads as a serious escalation rather than a mid-tier nuisance. First
  slice: the HX-1 pilot always spawns already suited; it doesn't climb into one standing in the
  world, and `Reinforcements.difficulty` has the same hook as `EnemyResponse.difficulty` but
  nothing sets it yet (contract zones' reinforcement waves, as opposed to hot zones' EnemyResponse,
  aren't wired to a contract's rating in this slice).

### Heavy exo: the HX-1 Assault Frame, first playable slice (Captain, 2026-10-16/17)

#### Added
- `exo_mech_heavy`, the HX-1 Assault Frame (`ExoMech`, `scripts/combat/exo_mech.gd`;
  docs/near_future_hardware.md 2.3): a heavy mech-class exo in the `exo` slot that is never picked
  up or put on from the inventory. Climb in from the interaction menu where it stands (3 s: you're
  put where it stood, facing its way, the hatch closing round you) and Climb out on yourself (the
  hatch opens, the suit is left standing where you were, you step down in front of it). Both clips
  are `CharacterModel.MECH_IN`/`MECH_OPEN`/`MECH_OUT`; the hatch (chest up, belly down, head unit
  back) follows them on every peer (`ExoMech.HatchRig`).
- Its armour is real `ArmorRules` armour (Captain's call over the doc's integrity pool): fifteen
  `VoxelArmor` plates on the parts they cover (Captain, 2026-10-17: AR500 steel throughout, IV chest, head unit, shoulders, caps and back;
  steel III belly; steel III++ forearms, thighs and shins; a III visor), their chips and integrity in
  the suit's state, like the LX-3's pads. A suit left standing is a `WorldItem` whose plates still
  take hits (into its state's "pads"), and climbing back in brings every chip.
- Real camo on armour: a `VoxelArmor` whose item says `"camo"` is painted in the wearer's camo
  pattern (`VoxelArmor.set_camo`, VoxelArt's own pattern), chips and scars still showing metal.
- Movement: it carries 260 kg (itself and 80 kg of kit); no sprint, jump, climb or prone; a fixed
  0.75 walking pace; no vehicle seat takes it. Its actuators take rounds like the LX-3's struts;
  disabled, the pilot carries all of it.
- `wg50_walker`, the WG-50 Walker Gun: a .50 BMG heavy machine gun (belt_50bmg) only a pilot can
  carry. It rides on the suit: climbing in puts it in your hands and your rifle on its rack.
  Held low and ready at the hip (`GearRig.LOW_READY_*`), up to the shoulder to aim. Voxel model:
  VoxelArt's "walker" style.
- One stands open on the vehicle range with its gun. Neither is sold yet: their price, repair cost
  and pilot training are the Captain's call (doc 2.3a).
- `mech` suite (`tests/mech_test.gd`) and `tests/mech_shots.gd` (art review shots).
- Captain's art round (2026-10-17, his refs): the suit is drawn 1.25x a soldier (about 2.3 m:
  `CharacterModel.suit_size`; its plates, hitboxes, eye and capsule grow with it, so it won't fit
  most doors), the pilot's body and kit hidden inside dark mechanical cores with only his head
  showing, the head unit sunk low between high shoulder humps and big pauldrons, heavier forearms,
  thighs and feet, a launcher pod on the back (art only), and the WG-50 redrawn as a six-barrel
  rotary.
- You get in from the back with the manual release (Captain, 2026-10-17, from AW's punch-out
  scene: "the full back opens, the legs too", like a zipper): standing behind it you hit the
  release panel (green button, warning triangle) and its back unzips, the power pack and back
  plates splitting at the spine, then the backs of the thighs, then the shins
  (`ExoMech.HATCH`, `ParkedHatch`); you're in it with your arms pushed into its sleeves, seen
  inside until it zips shut (`CharacterModel.MECH_RELEASE`/`MECH_IN`). Climbing out it unzips and
  you step back out behind it; it's left standing open. The back and the legs' backs are now
  their own AR500 plates (`back_r`/`back_l`, `thigh_back_*`, `shin_back_*`).

- Renamed the HX-1 Assault Frame (Captain, 2026-10-17: after the LX-3; the first name echoed AW's
  own Atlas).
- A downed suit, as in the scene (Captain, 2026-10-17): on a downed or dead pilot, a squadmate can
  **Punch out** (the release on its back; `ExoMech.server_punch_out`): the pilot comes out beside
  it and the suit is left lying face down, its back open (state "prone"). Kneel at its release,
  lie down into it, and it zips shut and pushes itself up onto its feet
  (`CharacterModel.MECH_RISE`, `ExoMech.RISE_S`). One lies face down on the vehicle range.

#### Fixed
- A round that met an armour piece's box but none of its voxels now carries on from just before
  that point, so a second piece whose box starts at the same spot is still met (`Ballistics`;
  found with the heavy exo's split leg plates).
### UH-60 walk-in cabin, helicopter doors, FFV riders, boarding and running out (Captain, 2026-10-17)

#### Added
- VTOL flight (`Helicopter.is_vtol`, data "flight": "vtol", "cruise_kmh"): the Petrel (320 km/h)
  and Razorback (270) bank into turns with the nose about level, accelerate and slow harder, and
  land by a straight approach to a hover then straight down: no J-hook.
- Hot drops: every insertion, and any landing with a known threat, comes in on a straight, low,
  fast approach with a hard flare and a quick let-down (`Helicopter.straight_plan`, `server_land_at`
  "hot"); a hot drop waves off only with more than 4 hostiles hitting it in 20 s (`HeliCall
  _shooters_hitting`). AI run out of the doors; it waits for them, then lifts.
- Fast-rope insertion (briefing: "Fast-rope from the hover"): a hover 12 m over the LZ, ropes from
  both doors, everyone down one at a time by the doors in turn, then away (`HeliCall._step_rope`,
  `Vehicle.server_fast_rope`, ropes drawn on every peer).
- The briefing picks the side a helicopter insertion comes in from (`Briefing.approach`,
  `HeliRoute.entry`'s side), re-planning its route.
- Pilots shown in the helicopters (drawn at the controls, `Vehicle._build_crew`).
- The Petrel's gun is an M2 .50 belly turret worked from the co-pilot's seat (`"gun"` "remote": the
  seat doesn't turn with it), crewed by a support crewman (`HeliCall._crew_gun`); its two door
  gunners are gone.
- Combat pilots: hit in flight, it jinks, drops lower and speeds up for a few seconds (`EVADE_*`).
- Fluid mantle (`SoldierMovement`): the ledge looked for along the way it runs, a jump into a wall
  or a press a step early counts, quicker on the move, one curve up and over, speed carried on.

#### Changed
- The UH-60 has no deploying boarding ramps (step "ramp": false: the mantle does it); sill riders'
  legs hang down to the ground.
- The UH-60M's cabin is a walk-in bay (`data/vehicles.json` "uh60" "bay": floor, walls, sliding
  doors, a step at each door; `VehicleArt`/`VehicleInteriors` hull and cabin rebuilt wider and
  taller), an open floor plan: only the 4-seat aft bench has seats; 4 kneeling spots (seat stance
  "kneel") and 3 standing spots on the floor, and 2 fire-from-vehicle riders per door sitting on
  the sill facing out, legs over the edge (seat "edge"; 19 seats: 2 pilots, 2 door gunners, 15
  passengers).
- Helicopter sliding doors (UH-60, Petrel, Razorback; `VehicleBay` door "roll_deg"/"pop"/"windows"):
  shut, each lies flush on its hull's skin (tilted to the flank's lean); opening, it pops out 1.5 cm
  past the hull, then slides back along its rail; each has windows after its airframe's design (the
  UH-60's two, the VTOLs' cabin window row carried across).
- FFV riders with the doors shut kneel behind the door facing out and move into their seat (the
  UH-60's: onto the sill) as it opens (`Vehicle._ffv_crouch`, `VehicleBay.open_fraction`).
- Kneeling (`Vehicle._kneel_feet`): the shooting side's knee up and its foot planted, the other knee
  on the floor (a right-hander's right knee up, a left-hander's left).
- AI take the FFV door seats first (`Vehicle._first_free_ffv`, also through `Helicopter.server_enter`).
- The Razorback: 3 FFV door seats a side (was 2), and its aft row of seats cleared into an exo bay
  with two standing spots (seat "exo", `Vehicle.exo_seat`/`_first_free_exo`; ~3 m headroom for the
  HX-1's ~2.3 m). Nobody else is put there; letting an HX-1 pilot ride there is the heavy-exo
  branch's to wire (its `server_enter` refuses suited pilots today).
- Riders on a seat with a canvas back (vehicles.json seat "back") sit back against it, nearly
  upright (`CharacterModel.SEAT_BACKED_PITCH`), their pack between them and the canvas
  (`Vehicle._pack_off`, `GearRig.pack_depth`).
- AI getting out of a walk-in bay on the ground run out (`Vehicle.server_run_out`, used by
  `HeliCall._unload` and `VehicleLayer.server_order_dismount`): up off the seat, a run to the door,
  down off the sill, out at the step's foot, instead of appearing beside the hull.

#### Fixed
- "That get anim is poor, it just floats up": getting into a bay seat from within
  `Vehicle.BOARD_FROM_M` of its door plays `CharacterModel.BOARD` for every peer. The door slides
  open, he steps up onto the sill (lead foot, push with a lean, trailing foot) with a hand on the
  grab handle by the doorway, walks in to his seat turning to face it, and sits down
  (`Vehicle._server_board`/`_board_pose`, `CharacterModel._boarding_bones`). Put in from far off
  (a mission's seating) or swapping seats, he's just seated as before.
### Air wing upgrades: the Razorback and friends (Captain, 2026-10-17)

#### Added
- Helicopter upgrade system (`HeliUpgrades`, `data/supports.json` "upgrades"): one-time
  company-wide purchases kept in the campaign save's economy section ("heli_upgrades"), bought
  from the base's Motor pool page (new "Air wing" section, `BaseUI._build_air_wing`, through
  `Economy.buy_heli_upgrade`/`server_buy_heli_upgrade`). Proposed prices, Captain's call:
  - Razorback heavy-lift VTOL, $120,000: transport, extraction and helicopter insertion calls fly
    `vtol_razorback` (more passenger seats than the Petrel; `HeliCall.model` from
    `HeliUpgrades.model_for`, its landing zones sized for it); resupply, medevac and cargo stay
    on the Petrel. A lost Razorback costs 1.8x the usual replacement. This is the "later unlock"
    docs/near_future_hardware.md 1.2 planned, through the existing money path.
  - Armoured cabin kit, $40,000: hits on a support aircraft do 30% less damage
    (`Vehicle.damage_mult`, set by `HeliCall` at spawn).
  - Fast turnaround crews, $25,000: every support's cooldown 40% shorter (`HeliSupports.cooldown_s`).
  A new campaign starts without them; outside a campaign the stock air wing flies.
- A contract's support budget is $23,000 a negotiation point (was $5,000; Captain, 2026-10-17:
  "enough to cover one heli exfil and the infil with one point in support": a transport's $9,000
  and an extraction's $14,000; `data/contracts.json` "support_per_point").
- AI getting into a helicopter take its fire-from-vehicle door seats first (Captain, 2026-10-17;
  `Vehicle._first_free_ffv`, through `Helicopter.server_enter` too, which picked the first cabin
  seat before).

### Floating site-box lootboxes, scope PIP black flash (Captain, 2026-10-16 playtest of v0.4.26)

#### Fixed
- Valuables/intel boxes at module loot spots (offices, command posts, desks -
  `WorldValuables.server_spawn_site_boxes`) floated about half a metre above the floor. They were
  placed at the same `ZoneModules.LOOT` anchor a `WorldItem` already rests at, but that anchor is
  a *drop* height for the `WorldItem` (a `RigidBody3D` that falls and settles onto the real floor
  on its own) - a `WorldCache` never falls, so it stayed exactly at the drop height instead of the
  floor. Open-terrain caches (`_spawn_site`) were never affected - they're placed straight on
  `ground_point()`, which `WorldCache`'s own shape already accounts for, same as `SupplyPallet`.
- A tube scope's or a flipped-up magnifier's picture-in-picture could flash black for a frame on
  a magnifier flip, an optic swap, or a window/viewport resize - all three resize the scope's
  `SubViewport`, and Godot doesn't repaint one in the same frame as a resize or its first creation,
  so `_draw_scope_pip` could read a stale or blank texture that frame (`GunSight._scope_stale`).
  Distinct from the by-design black ring mask around the glass (`_draw_ring`), which is untouched.


### Enemy high command, fuller zones, urban fights (Captain, 2026-10-17 night)

#### Added
- Enemy high command, Phase 2 (docs/enemy_high_command.md): the enemy commander judges you
  from what his men report (loud fire reads as more of you; noise far from a sighting gets a
  probe, not a hunt), spends finite reserves, probes and reoccupies lost sites, retakes ones you
  left a defender on, falls back when half his men are gone (outposts abandoned), and remembers
  how the zone went across deployments (cautious after losses, bolder after wins, easing back
  over the days). His orders go out on the enemy net (looted radios hear them).
- The commander is a person: the HQ's officer, or an HVT at the HQ in the enemy's uniform and
  medium armour with two bodyguards; hit the HQ and they run for a QRF base while he calls a
  relief force. Capture or kill him and the zone goes headless for 10 minutes. After you take
  out a QRF base, the follow-up contract is to capture him; the employer also warns you when a
  counterattack is massing. Dev tools: PgUp readout shows the commander's state.
- Eleven new contract zones, four on new terrains (highland moor, river valley, badlands),
  three on procedural terrains (two presets blended by the zone's seed), and two hot zones
  (Crow's Pass, Reed Delta).

#### Changed
- Outposts gain 2-3 buildings, villages 1-6 more houses and shops, compounds 1-2 buildings
  (generated round the hand-built core, where there's room).
- Woods sprawl: bigger, thinning to straggling trees at the edge, with outlying clumps.
- Towns are blocks, not a strip: back rows across alleys onto back streets, open lots,
  sandbag barricades and rubble in the streets. Defenders hold deep inside (back rooms), a
  reserve moves to the side being hit, hurt or isolated defenders fall back building to
  building, and in hot zones the commander sends a relief force into the streets.

### AI orders and rescues, dragging, enemy AI, voices, shop (Captain, 2026-10-17)

#### Changed
- Squad AI follows the order of command: a player's Move (until it gets there), Hold and
  ordered tactics come before fighting and casualty care ("B team not responding" was its own
  fighting and casualty care outscoring the player's orders). Holding, casualties near the spot
  are still seen to.
- Rescues under fire only when covered: the rescuer goes if it can throw smoke, a squadmate is
  putting fire on the shooter, the shooter is pinned or smoke is down; otherwise it fights and
  covers until one of those is true.
- Dragging and carrying: the AI turns to the way it's going (the casualty trails behind), and
  drags to the nearest spot that hides someone lying down, away from the shooter, without long
  detours.
- Enemy AI: sees and engages out to 300 m (was 200; insurgents open up at 240 m, regulars at
  280 m); pushes toward you only after 15 s out of sight (was 6), only to cover and only while
  its morale holds; shaken, it holds its cover instead of searching the kill zone.
- Voice callouts sit under the gunfire and ambience: 10 dB down spoken, 13 dB over the radio.

#### Added
- Shop: a search box (filters what's for sale and what you can sell as you type) and a "Sell
  from the stash" list with Sell and Sell all.

### LX-3 armour and helmet, the climb order, supports runner budget (Captain, 2026-10-16/17)

#### Added
- LX-3 armour pads: twelve Steel III++ pads on the frame (shoulders/upper arms, forearms, thighs,
  shins, stomach, collarbones, upper back, spine pack) that are real per-part armour, not art:
  each is a `VoxelArmor` piece on its body part's bone, chipping, denting, holing and wearing
  through under `ArmorRules` like any plate. A stop lands its impact on the part under it; a round
  that gets through goes on into the body. Their damage lives in the frame's item state, so it
  travels with the frame and repairs cover it. Spall-coated, and the frame keeps spall off arms
  and neck. Limb pads are rounded sleeves over front, outer side and back.
- LX-3 Visor Helmet (`helmet_lx3`, $6,500): a medium IIIA shell with a face guard bolted on below
  its rim (cheek plates on side hinges, a mask with a respirator block, a nape guard, a neck
  seal) and a black visor that stops fragments and spall only. Bullets hole the visor and plates
  like any armour, and the face shows through.
- Squad order "Climb up there" (Move > 9): selected AI squadmates go to a wall top or roof, climb
  every ledge in the way and hold up there. The jump key's mantle now works for AI too, and a
  working LX-3 frame climbs 1.3 m higher (3.2 m: compound walls, low roofs).
- The LX-3 and its armour take the wearer's side's kit colour (coyote with the contractors'
  multicam, matching the plate carrier), with panel seams and ridges.

#### Changed
- LX-3 Assist Frame: $45,000 (was $6,500), 14 kg with its pads (was 9). A starting company
  ($150,000) can field two LX-3 sets with money left over, not three.
- LX-3 frame art: slimmer and darker, hinge drums, pistons, boot stirrups and a jointed spine.
- `tools/run_tests.sh`: the supports suite gets 780 s (`suite_timeout`). Its host's own checks
  take about 460 s before the late-joining client's resupply flies, so 480 s killed it mid-flight
  and it read as a hang (R1500, R1503; green with the budget: R1504).

### Near-future hardware: VTOL dropship, VT-14/Razorback tiers, light exosuit (Captain, 2026-10-16)

Design doc: [docs/near_future_hardware.md](docs/near_future_hardware.md). Contractor's setting is
near-future sci-fi, not present-day only (Captain, 2026-10-16) — this is the first deliberate
near-future content, learned from *Call of Duty: Advanced Warfare*'s Warbird/Goliath reference art
the way `movement_rules.gd` learns from Tarkov's inertia; no COD:AW trademarked name ships.

#### Added
- VT-14 Petrel: a twin-ducted-rotor VTOL (`vtol_petrel`) replaces the UH-60M Black Hawk for every
  player-faction support call (resupply, transport, extraction, medevac, cargo). Flies through the
  existing generic `Helicopter` class unchanged (J-hook landing, contour flight) — new stats and
  voxel art only, no new propulsion physics. The UH-60 stays in the game as world content (rescue
  wrecks). Walk-in cabin, toggleable bay doors, folding boarding ramps, FFV door seats for players
  and AI gunners.
- Razorback VTOL (`vtol_razorback`, Captain's own name): a bigger, higher-capacity second VTOL
  tier, same bay/door/ramp/FFV treatment as the Petrel.
- LX-3 Assist Frame (`exo_frame_light`): the first exosuit tier, a new `exo` inventory slot worn
  over the vest/plates/pack (armor untouched). Working, it carries 30 kg of the load (speed/
  stamina see that much less load). Its struts can take rounds (into an arm/leg, or the spine pack
  from behind): worn down, it's disabled — no assist, full load back on the legs, its status light
  red instead of green. Its struts, hinges, cuffs, spine pack and shoulder pylons are drawn on the
  body (`ExoFrame`, `GearRig`).
- `tests/vtol_shots.gd`, `tests/exo_shots.gd` and `tests/shot_window.gd`: windowed screenshot
  scripts for vehicle/gear art that never take focus or the mouse (`ShotWindow.stay_out_of_the_way`),
  safe to run alongside someone else at the keyboard; `--headless` runs the same script as a quick
  sanity check with no window.

#### Changed
- Landing-zone ground clearance is now per-model (`LandingZone.clear_for`), not one constant: the
  Petrel's ducted pods clear the ground at 8.0 m, tighter than the UH-60's 9.5 m.

Suites: `vtol_shots`/`bay`/`heliflight`/`exo`/`mantle`/`smoke`/`armor` green. `vehicles` has 3
pre-existing failures unrelated to this work (none of the touched files differ from `dev`): 2
stale sound-name assertions fixed in this pass; one open-bed hit check diagnosed but left for a
follow-up (diagonal shot vs. the technical's bed wall geometry, not a VTOL/exo regression).

### MG/AR silhouettes, bolt-action snipers, suppressors (Captain, 2026-10-16)

#### Changed
- The PKM, M240B and M249 no longer share one `_rifle_mg` silhouette. Each has its own
  (`_rifle_pkm`, `_rifle_m240`, `_rifle_m249`, `VoxelArt`; `model_style` "pk"/"m240"/"m249" in
  `data/items.json`), built from reference photos: the PKM is wood-furnitured (handguard, grip,
  skeleton stock) with a perforated barrel jacket and its ammo box slung off the receiver's LEFT
  side; the M240B is all-black, the longest and bulkiest of the three, with a top-mounted carry
  handle over a top/right feed tray cover and a side-folding skeletonized stock; the M249 feeds
  from a box directly UNDER the receiver, has large top-mounted heat-shield vents, a small
  STANAG mag-well door, and a slimmer collapsible CAR-style stock. Irons are unchanged (AK-leaf
  for the PKM, rear aperture for the other two).
- The L85A2, C8 and HK416 no longer fall through to the generic AR silhouette they shared with
  the M27 (none set a `model_style` before). The L85A2 is a bullpup (`model_style: "bullpup"`):
  its magazine and long receiver sit behind the pistol grip, running to the shoulder plate with
  no stock past it, on a modern-upgrade flat full-length rail (a low red dot replaces its old
  prism sight). The C8 (`"carbine_short"`) is a shorter-barrel M4-pattern carbine with a longer
  exposed, notched buffer tube reading as collapsible. The HK416 (`"piston_ar"`) carries a
  piston rod over its handguard from a taller gas block, instead of the AR family's hidden
  direct-impingement tube.

#### Added
- Two bolt-action rifles: the Mosin-Nagant 91/30 (`mosin9130`, 7.62x54R, a PU scope, 5-round
  stripper clips — `clip_762x54r` — and its own wood-stocked voxel model with a visible bolt
  handle, `model_style: "mosin"`) and the Springfield Heatseeker (`springfield_hs`, a modern
  6.5 Creedmoor precision chassis rifle — a new `65cm_eldm` round, `data/rounds.json` — with a
  detachable 10-round box magazine, a folding chassis stock, an M-LOK handguard and a big
  precision scope, `model_style: "chassis_bolt"`). Both use a new `"bolt"` fire mode at 40 rpm;
  no new firing code was needed; the engine's existing per-shot rpm pacing already gates the
  next shot the bolt-cycle delay represents.
- Suppressors: an attachment (`Suppressors`, mirroring `Optics`) that mounts on a threaded
  weapon's muzzle from the inventory, the same way an optic mounts on a rail. Mounted, a shot
  is treated as suppressed — the quieter sound, a dimmer tracer and a much shorter alert radius
  the engine already had for a static "suppressed" stat, just never wired to anything players
  could attach themselves. `VoxelArt._with_suppressor` adds the can to a rifle's muzzle
  generically, over every silhouette at once, so a new one never needs its own suppressor boxes.

### Scopes are a real picture-in-picture (Captain: "better scopes and PIP", 2026-10-16)

#### Changed
- A tube optic's (LPVO, prism, DMR scope) magnified picture is now a genuine PIP: a `SubViewport`
  with its own `Camera3D`, synced to the player's eye every frame and composited into the
  eyepiece ring (`GunSight._draw_scope_pip`). The player's own camera no longer narrows its field
  of view while behind the glass — it eases back to the normal (peripheral) view instead, so the
  gun and its surroundings stay visible around the scope picture, the way a real scope only
  magnifies what you see through it. The reticle (mil-dot, LPVO cross, chevron/BDC) still reads
  true at any power; the glass picture renders at `GunSight.SCOPE_RENDER_SCALE` (0.65x of the
  ring's screen size, stretched to fit) rather than full resolution, to bound the added render
  cost. The first-person weapon/arms are on their own render layer
  (`PlayerInput.VIEW_MODEL_LAYER`) so they don't show up (huge, in the way) inside the magnified
  picture, and stay visible in the player's own (now unzoomed-while-scoped) peripheral view
  instead of vanishing entirely, as before.

### Squad callouts know what's actually going on (2026-10-16)

#### Added
- Contact calls are pre-rendered per clock position, close range getting its own urgent line
  (`Contact, two o'clock, 80 m`, voiced "contact_<clock>[_close]"); the subtitle keeps the exact
  distance, same as before. Enemies' contact calls get the same treatment and fall back to their
  plain line in Russian/Farsi (not translated for this pass).
- A squad member who's carrying intel calls out the kind of enemy site it just revealed ("Got
  the HQ marked!"), voiced per site type (IntelReveal.intel_found, Callouts).
- Reloading on the last magazine of a weapon's ammo gets an ammo-status line naming the weapon's
  class, not its caliber ("Last mag for the rifle!"): rifle, mg (belt-fed/LMG) or pistol.
- `Callouts.voiced_path` falls back from a dynamic id to its less specific prefix (down to the
  bare category) when no pre-rendered line exists yet, so a new template slot degrades to the
  old generic line instead of going silent; `tools/voices/gen_callouts.py`'s `LINES["en"]` has
  the new combos (contact x8 clock positions x2 ranges, 5 intel site types, 3 ammo classes) to
  render with Piper. Scope stays bounded ("nothing insane"): these three categories, English
  only, one phrasing each.

### The salt flats stop glaring (Captain, 2026-10-14)

#### Changed
- The Salt flats zone ("this terrain is an actual eye sore": a near-white pan brighter than the
  sky, meeting it at a hard line, nothing on it) is a grey-beige salt pan darker than the sky:
  damp patches, crust polygons and tyre tracks near you, shallow damp channels, gentle swells,
  mud, a berm and low rocky mesas round the edge, dead bushes, rocks and rubble at the margins
  and round the compounds and roads (the middle of the pan stays open), a softer sun and lower
  exposure, a warm horizon haze, and far ridges along the horizon. Other zones are unchanged.
  Numbers in docs/terrain_presets.md (Proposed); the world suite checks the pan's brightness
  against the sky, its relief and where its scatter goes.

### The red dot is a micro red dot's size (Captain, 2026-10-14)

#### Fixed
- The red dot sight (the M4A1's and Mk18's own, `optic_red_dot`) was a 9 cm long box with a
  3 x 4 cm window in a 4 x 5 cm housing, longer than the holographic sight, and in first person it
  stood out as a big box on the right of the view (and filled the lower right when the weapon
  pulls back near a wall). It is now an Aimpoint T-2 sized sight: a 3 cm tube 6.5 cm long round a
  clear 2 cm window, with its caps and brightness knob, on a slim riser and rail clamp, 5.5 cm
  from the rail to the top cap (`VoxelArt.optic_boxes`, `RED_DOT_LENGTH`). The line of sight,
  where aiming puts your eye and the dot, is unchanged; other optics, the rifle and the
  first-person view are unchanged. The gameplay suite checks its size and that its window is
  clear front to back round the line of sight.

### Vehicle interiors and windows (Captain's side, 2026-10-13)

#### Added
- Seated in first person you see a cabin instead of the inside of a solid hull: the M-ATV,
  MaxxPro, every technical (Hilux and Land Cruiser cabs), the AAV-7 and the UH-60 have their
  cabins hollowed and furnished at the models' 5 cm voxels: a seat under each enclosed seat's eye,
  a dash with the instrument cluster, radio and steering wheel before each driver, an instrument
  panel, cyclic and collective before each pilot, and windows you can see out of (glazed through
  the wall, tinted glass). The AAV's driver gets a vision slit in the bow and its cupolas' and
  weapon station's vision blocks are see-through; gunners' hatches are cut in the M-ATV's and
  MaxxPro's roofs (`scripts/art/vehicle_interiors.gd`).
- A new see-through palette entry (`VehicleArt.P.WINDOW`) on its own surface with a glass
  material; a burnt-out wreck's windows go opaque and dark with the rest of the hull.

#### Changed
- Hit volumes and protection are unchanged: interiors and see-through windows are drawn only in
  the canvas's `look`; the voxels rounds and fragments meet (`VehicleHull.first_solid`) are the
  same as before, windows included (still `P.GLASS`, still stopping what the hull stops). Damage
  marks (scuffs, scorch, a hole's ring) are only drawn where the look has a voxel, so a hidden
  solid cabin never shows as a black lump inside. The few visual-only differences: the M-ATV's
  cab back wall (rounds still pass where they did), the gunners' hatches, the AAV driver's slit.
- UH-60: the crew chief's and door gunner's eyes (x 0.95 to 0.72) and the four outer
  passengers' (x 0.9 to 0.75) moved in from the fuselage wall, which they sat in or outside of.

#### Known gaps
- Bradley, Abrams and AH-1Z have no interiors yet (nothing spawns them for players).

### Audit fixes: 26 findings of the 2026-10-13 audit (cghath's side, 2026-10-13)

The audit (`docs/audits/SUMMARY.md`, parts 1 to 3, at `fcae676`) found 3 high-priority and 23
medium findings. All 26 are dealt with: 25 fixed, A3-07 marked pending. Each has a regression
check in the suite that owns the code.

#### Fixed

- **Campaign saves are never deleted because they can't be read** (A1-01, high): an unreadable
  save, backup or interrupted write is renamed aside (`<file>.unreadable-<date>-<time>`) and the
  backup or a finished interrupted write loads instead. Only with nothing readable does a new
  campaign start; its old zone saves are moved aside ("orphaned") and the host is told where.
- **A missing save loads its backup** (A1-02, high), campaign and zone; saving checks every step,
  so the last good save is always on disk.
- **Loot all no longer duplicates an aid bag's contents** on a backpack (A2-01, high).
- Saves from another version, or with sections, records or voxel edits of the wrong shape, are
  refused (campaign) or skipped record by record (zone) (A1-03).
- A save that fails to write says "Campaign NOT saved: ..." instead of "Campaign saved" (A1-04).
- Malformed contract requests are answered "Bad request" instead of a host script error;
  negotiation terms must be plain numbers (A1-05).
- A reload no longer finishes on a different gun or launcher of the same model (A2-02).
- No IV below a tourniquet; with tourniquets on all four limbs only an IO is offered (A2-03).
- Muffled hearing clears when you leave the session or the level changes (A2-04).
- The medical menu's item list scrolls (wheel, arrows, page keys, scroll bar); off-screen rows
  can't be clicked; the panel fits shorter windows (A2-05).
- **The launcher has its own tile on the inventory screen**: what's loaded, Stow, Pack on top and
  Drop; drag to stow, drop or pack; a packed launcher dragged onto the soldier swaps with the one
  on the shoulder (A2-06).
- A pack dragged from the ground into a container is stowed, not swapped with your worn pack
  (A2-07); a crate or objective case dragged onto a container goes to the hands, as a click does.
- Squadmates picking their packs back up take their own pack by item, wherever it rolled (A2-08).
- "Scavenge that body" and AI scavengers use where the body lies (A2-09), and extraction counts a
  body or a downed squadmate where it lies (A3-03), per CLAUDE.md's reach rule.
- A raid's clear-area bonus waits until the target's garrison has spawned (A3-01).
- A civilian hurt only by a grenade's blast counts against the thrower, for fines and reputation,
  and so does a later death (A3-02).
- AI building scans no longer carry over between levels at the same coordinates (A3-04).
- A wall blown open in a zone module stays open for sight lines, rounds and AI paths after the
  module streams out (A3-05).
- Repair, refuel and salvage stop if the vehicle leaves the worker mid-job (A3-06).
- **Test runner**: an import that logs a SCRIPT ERROR or parse error fails the run even when the
  editor exits 0 (A3-08); logs are written straight into the kept run folder, and a run stopped
  part-way is a FAIL (A3-09). New `tools/run_log.sh` holds the logs parent, run number (taken under
  a lock) and branch-sha for the runner and the build tool.
- **CI** keeps each suite's own logs (import, suite, host and client) and uploads them as the
  artifact `test-logs-<suite>-attempt-<n>` whatever the verdict (A3-09).
- **Test builds** get their own numbered folder (`builds/contractor-<date>-<time>-B<number>-<label>-<sha>/`),
  an `index.txt` line and a kept export log; a failed export fails loudly (A3-10). With Zylann's
  Voxel Tools release template installed (`template_release/` beside the editor, or
  `CONTRACTOR_TEMPLATE`), a build also has a standalone `Contractor.exe` and a
  "Contractor (dev tools).bat" that starts it with `--dev`.
- Tests: the net test's client no longer deletes the host's save fixture (A1-06); the contracts
  replication test keeps a hostile in the compound so its objective stays active (A1-07).
- **A bearer ordered to move no longer lifts the casualty he just laid down, over and over**
  (found by CI on this branch; on dev too): the body's ragdoll settles up to about 2.6 m from
  the lay spot, which one check counted as "not there yet" and another as "laid". Both now use
  one test (`SquadAI._lies_at`, measured to `body_point()`). The squad suite's contact check
  waits for an AI physics step; the roles callout check uses squadmates tactics never speak
  through.

#### Changed

- **Faction doctrine numbers are pending** (A3-07): engage range, reaction, aim, bursts, frags,
  morale and movement in `data/doctrines.json` are marked pending in code and data; the AI doesn't
  use them yet (only the doctrine type shapes squad tactics). Wiring them in retunes every side's
  fighting, so it's left to Captain's tactics work.

#### Known gaps

- Quit from the pause menu still quits when the save fails (the failure is shown and logged).
- A civilian at a blast's edge with only ringing ears counts as a wounded casualty (A3-02; a design
  call).
- A peer that never streamed a module in still shows its original walls in that module's proxy
  until it streams in once (A3-05).
- Load-dependent test flakes seen during the work, also on the unchanged base: squad "Give me
  ammo", animations dragger hand placement, people's late-join client.

### Wave 5b: helicopter supports, AAVs, the LHD, the motor pool (cghath's side, 2026-10-12)

#### Added

- **Support menu** (command menu, 0): helicopter transport, resupply and extraction, and an AAV
  submenu. `Supports` (`scripts/supports/supports.gd`) is the seam: support commands, where
  supports launch from (the LHD, the friendly FOB's side, else the map edge), and a can-fly
  check for weather later.
- **AI-flown UH-60 Black Hawks** (`Helicopter`, a `Vehicle`): take off, cruise about 90 m above
  the ground following the terrain, approach, flare, land and leave by their origin. Rotors
  turn and the engine sounds; smooth for clients and late joiners. 7.62x54R and launchers hurt
  them; a rotor, engine or crew kill brings one down, and it crashes and burns with everyone
  and everything aboard. A support lost is gone for the rest of the op (Captain).
- **Calls**: at your map marker, at the spot you look at, or on smoke of the right colour
  (resupply green or yellow, transport green or blue, extraction purple). Without a mark it
  comes in and loiters near the squad, keeping away from fire, until it sees its smoke.
  Supports cost money (the contract's support budget first, then cash), have cooldowns, one of
  each kind at a time.
- **Landing safety**: a spot too steep (over 15°, the design doc), built up, blocked or with
  people on it lands at the nearest safe spot within 100 m (Captain); enemy fire never moves it.
- **Resupply** sets down a supply pallet: magazines and rounds for the squad's weapons, medical
  items, grenades and smoke (`data/supports.json`).
- **Transport** (hot zones only) picks up the squad (players through Left Ctrl, AI ordered in,
  the downed loaded) and flies it to the caller's map marker. Hot-zone briefings offer each
  insertion point by Black Hawk: the squad starts aboard and is flown in.
- **Helicopter extraction** is extraction's ride: its landing spot is the extraction point; the
  squad, the AI brought along, the downed, cuffed or friendly HVTs and the items set down in the
  point go aboard, and lifting off ends the deployment with what's aboard in the report. The
  countdown extraction still works without it.
- **The LHD** lies offshore on every zone whose terrain preset has a sea (a placeholder ship,
  never attacked); supports start from its deck. Inland they come from the friendly FOB's side
  of the map. New preset `amphibious_coast` and test zone `coast`.
- **Amphibious vehicles**: the AAV-7 floats, swims at 13 km/h on its waterjets, steers and drives
  up the beach. Other vehicles flood and stall past their fording depth.
- **The AAV support** (Support, AAV): an AAV and its AI crew from the LHD (it swims ashore) or the
  FOB (it drives in) for $12,000. Orders: move there, hold, follow me, squad get in, dismount,
  return to base. Its gunner fires the M2. Hot zones and coastal contract zones; refused in
  mountains, on ground too steep, or when the company can't pay. One at a time; lost with
  everyone and everything aboard, and no other comes that op.
- **Motor pool**: the company's own vehicles between deployments (campaign section
  `motor_pool`), starting with one M-ATV. Pick them on the briefing to bring them; ones that
  extract with the squad come home with their damage, fuel and cargo; ones left behind are
  lost. The base's motor pool sign lists them and books repairs (money and days). The base hub
  itself is unchanged: the friendly-FOB conversion waits for a decision.
- **Vehicle QRFs** in hot zones (Captain's hook): some QRF waves ride in technicals, get out short
  of the contact and leave the gunner on the DShK.
- **State dumps** list each vehicle (driver, passengers, damage, fuel, AI order) and each support.
- **Dev tools**: with `--dev`, outside a deployment, helicopter calls are free and transport flies
  outside hot zones; `]` calls an AAV to you anywhere, free.
- **Tests**: `supports` and `aav` suites (host and client).

#### Changed

- Vehicles hold grades up to 35° within their grip (an AAV-7 used to stall on 8°).

#### Fixed

- A navigation chunk that is all sea no longer errors (an empty triangle list).
- The `antiarmor` M-ATV spall check is deterministic; the `missions` charge check follows how the
  man actually moved on rocky ground; the `aav` swim check samples deep water only.

#### Known gaps

- The helicopter crew is simulated (no crew bodies after a crash); no rotor wash, door guns or
  autorotation. Typed grid references only as a command argument (`grid:<ref>`).
- On Captain's `coastal_lowland` sea the LHD sits about 50 m off the beach in shallow water; a
  wider, deeper sea would suit it (Captain's call). AAVs there are untested beyond the test zone.
- Players can walk on the seabed; the map doesn't draw the sea.

### More bone simulation (Captain's picks, 2026-10-12)

#### Added

- **Open and closed breaks, a pelvis with a pelvic binder, collarbones, hands and bullet ribs** (`WoundModel` "Bone sim" constants, `BodyMap.BONES`): a bullet or fragment break is open with a chance by round class (a femur's higher), a fall's mostly closed; an open break bleeds on its own and needs a bandage or gauze besides its splint (two tasks in the plan of care, the medical menu and AI care), and moving on an unsplinted broken leg can turn a closed break open (noted in the session log) and raises a femur's internal bleed. A broken pelvis bleeds heavily inside and can't walk or stand (crawl, or be carried) but can still shoot; the new **Pelvic Binder** item (`data/items.json`, in the medic's kit) cuts its bleed and the legs stay out until the mission ends. A broken collarbone adds rifle sway and slows aiming down sights (pistols unaffected; a sling, the splint, eases it), a broken hand counts as a broken arm, and a bullet through an unplated chest can crack a rib. No spine injuries.

### Triage cards and bleeding HUD (2026-10-12)

#### Added

- **Triage cards**: the medical menu has none / minimal (green) / delayed (yellow) / immediate (red) / expectant (black) buttons for the casualty (host request `Soldier._server_set_triage`, reach-checked to `body_point()`, replicated in `net_state` "tg"; shown in Check condition). AI responders take immediate before delayed (and uncarded) before minimal, expectant last. Also: a small body silhouette in the HUD corner while you have an untreated bleed, fracture or tourniquet.

### Sound (Captain's side, 2026-10-12)

#### Added

- **Sound** (`Sfx` autoload, `data/sounds.json`, docs/sound.md): generated, stylised sounds for
  gunshots (near and far, suppressed), bullet cracks passing close, impacts (dirt, plate,
  body), explosions, flashbangs, reloads, throws and footsteps; heard from each player's own
  position, delayed by distance, within the ranges the AI hears. Real recordings in
  `res://audio/sfx/` override any sound. `tools/export_sounds.gd` writes them as WAV files.
  New suite `sound`.

### Session-log event lines and a movement-test fix (2026-10-12)

#### Added

- **Session logs now record casualties, care and returns to base**: a soldier going down or
  dying (who, cause, body part, who hit them and from how far; `Vitals.last_cause`), every
  treatment (`Soldier._treat` / `_timed_care`: treater, patient, item, part, done / interrupted
  / refused and why) and Return to Base / revert (`BaseHub`).

#### Fixed

- **Movement suite flake** (stand-up after the ragdoll): the test put the body back before the
  ragdoll had finished standing it up where it lay, so the walls were built round the wrong spot.

### Bug-report key and AI overlay (2026-10-12)

#### Added

- **Bug-report key (Insert, any build)**: a note panel (Enter saves, Esc cancels) writes
  `report-<n>.txt` and `report-<n>.png` into the session's folder: the note, time, zone and
  seed, `SessionLog.state_text` (every soldier, the AI's intents) with the player's inventory
  and wounds, and the last log lines. `BugReport.save(note, node)` is the callable the tests use.
  The pause menu shows the key. `SessionLog.state_text` now includes the local player's
  inventory and wounds.
- **AI debug overlay (Delete, dev tools, host)**: labels over AI within 80 m (the nearest 16)
  with intent, status, target, combat mode and suppression, and a line to where each is heading
  (`SquadAI.destination()`), refreshed 4 times a second.

### Medical menu, slice 1 (Captain's side, 2026-10-12)

#### Added

- **Medical menu on H** (`MedicalMenu`, `scripts/ui/medical_menu.gd`; inspired by ACE3's): opens
  on the person you look at within treatment reach (measured to `Soldier.body_point()`), else
  on yourself. A body diagram of the 14 parts, clickable, coloured by state (bleeding by
  severity, untreated, treated) with TQ, splint, dressing, seal and IV/IO markers; the chosen
  part's injuries in words and every medical item you carry, greyed out with the reason when
  it can't be used there now; choosing one sends the same `_server_treat` request as the
  interaction menu's Treat (and Remove tourniquet its own). Signs in words (numbers only with
  a pulse oximeter). An activity log, local to the treater for now (what you chose, and the
  changes seen while the menu was open). H or Escape closes it; while open it has the mouse
  and the keys. Reads replicated state only, so it works on clients. Test: medical suite
  "Medical menu (H)".

#### Changed

- **Quick-treat moves to Shift+H** (`quick_treat`, `Controls.SHIFT_KEYS`), same behaviour as the
  old H. The `use_medical` action is now `medical_menu`.

### Terrain presets (2026-10-12)

#### Added

- **Terrain presets** (`data/terrain_presets.json`, `docs/terrain_presets.md`): coastal_lowland (with a sea along
  one seeded side), salt_flats, desert_wadi (carved riverbeds), rocky_ridge, scrubland, temperate. Chosen by the def's
  `terrain`, name hints or region, and carried in the def. `ZoneScatter`: seeded rocks, scrub and trees by zone
  area (MultiMesh; large rocks and trees have collision and nav boxes).

### Wave 5a: vehicles and anti-armour (cghath's side, 2026-10-12)

#### Added

- **Captain's vehicle models in the game**: `VehicleArt` (14 voxel models at 5 cm: UH-60,
  AH-1Z, AAV-7, MaxxPro, M-ATV, Bradley, Abrams, seven technicals) copied from his asset
  repo to `scripts/art/vehicle_art.gd`. Physics layer 7 is "vehicles".
- **Vehicles** (`Vehicle`, `scripts/vehicles/`, numbers in `data/vehicles.json`): host-simulated
  Jolt bodies with raycast suspension; wheeled ones steer with the front wheels, tracked ones
  skid-steer. Clients send throttle, steer and brake and see smooth replicated movement.
  Fuel, an empty tank, jerrycans.
- **Seats**: per model (M-ATV 4 + gunner, MaxxPro 6 + gunner, technical cab, bed and gunner,
  AAV-7 3 + 21, Bradley 3 + 6, Abrams 4; the UH-60's seats wait for the helicopter supports).
  Get in, switch seats and get out through Left Ctrl action points (doors, ramp, cargo,
  service). Squadmates take "Get in that vehicle" and "Get out" (command menu: Mount). A downed
  or dead body can be loaded into a seat and pulled out again.
- **Cargo**: each vehicle carries an inventory with litre and kg limits, loaded and unloaded
  through Left Ctrl; it feeds the mounted guns' belts (.50 M2 on the MRAPs, DShK on the
  technical).
- **Vehicle damage**: hit zones (hull, engine, wheels or tracks, fuel, crew, cargo) with armour
  by class. Small arms bounce off armoured vehicles; 7.62x54R and up penetrate or disable them
  (Captain's rule); a technical's doors stop nothing; IFVs and tanks stop .50 on most faces.
  A round that gets through carries on into the people inside. Engine hits slow then stop a
  vehicle, wheel and track hits cripple it, fuel hits leak and can start a fire. Hits carve
  holes and scorch into the vehicle's own 5 cm hull.
- **Fire and wrecks**: a burning vehicle kills whoever stays aboard and destroys its cargo,
  then becomes a blackened wreck that can be salvaged for parts. Vehicles and wrecks are saved
  with the zone and come back when the campaign returns to it.
- **Field service**: timed repairs with a repair kit, spare wheel, track links, engine parts or
  a battery.
- **AI drivers**: `server_drive_to` and `server_follow_path` on the navmesh, with stuck
  recovery.
- **Bodies and vehicles**: a vehicle wakes a settled ragdoll ahead of it and pushes standing
  soldiers aside; running someone over is blunt trauma through the wound model.
- **Vehicle range**: a main-menu debug level with an M-ATV, MaxxPro, technical and AAV-7, and
  `VehicleLayer.server_place_parked` so zones can park vehicles.
- **Anti-armour launchers** on a new launcher slot (key 3): AT4, RPG-7 (PG-7V HEAT, OG-7V frag),
  Javelin (hold aim 2.5 s to lock; top attack climbs and dives onto the roof, or direct attack),
  MAAWS (HEAT, HE, HEDP), NLAW (flies over and fires down, or direct), SMAW (HEDP, thermobaric).
  Rounds fly as host-simulated projectiles with motors, drop, arming distance and
  self-destruct, seen by every player. Data in `data/warheads.json`.
- **Warheads by round type**: shaped charges penetrate armour by mm (V1 decides what that does
  to the vehicle) and the jet kills whoever is in line inside; HE and HEDP blow craters in
  walls, HEAT bores a narrow hole, thermobaric clears rooms; fragments and overpressure wound
  people through the wound model; a direct hit is lethal.
- **Backblast**: a cone behind the tube, lethal close in and injuring further out; a wall or a
  vehicle right behind reflects it onto the shooter, and a small room fills with it. Javelin
  and NLAW soft-launch.
- **AI launchers**: insurgents sometimes carry an RPG-7 and use it on vehicles and groups behind
  cover, never on a lone soldier in the open ("Backblast clear!"); a squadmate with a launcher
  fires on order (command menu: Action, "Fire launcher there").
- **Items**: launchers and rounds (RPG-7 and its rounds loot and sell-only), jerrycan, spare
  wheel, track links, repair kit, vehicle battery, engine parts, .50 and 12.7x108 belts.
- **Tests**: `vehicles` (host and client) and `antiarmor` suites, including launchers against
  the real vehicles.

#### Fixed

- **Launchers against real vehicles** (wave 5a integration): a shaped-charge jet that gets
  through a hull goes on into the cabin and kills whoever is in its line; the crew takes one
  spall pass (the vehicle's), not two; rockets meet a vehicle only where its 5 cm hull is, so
  one through an open bed or over a hatch flies on; riders in open seats take blast and
  fragments like anyone, enclosed seats shield; a launcher can't be fired from a seat; a
  shooter who leaves while the round flies no longer breaks it; the AI stops firing at
  burning vehicles. Proposed: `Warheads.TOP_PROBE_M` 3.0 m.
- The `people` suite's client sometimes never reported: the host pushed its checklist when
  the client first connected, and a connect that timed out while the client was still
  building its world lost it (and Main reloaded the scene under the test). The client now
  joins by itself, retrying, and asks for its checklist once in; the antiarmor client too.

#### Known gaps

- The launcher slot has no tile on the inventory screen yet (that screen's layout is Captain's
  side's); key 3 and Alt+G work.
- No AI gunners or turret rotation yet; no crash damage between vehicles or against walls;
  grenades and charges don't damage vehicles except a charge placed on one.
- Structure edits are lost when a VoxelWorld block unloads far from every viewer.

### Session logs (Captain's side, 2026-10-12)

#### Added

- **Session logs** (`SessionLog` autoload): every playtest (editor or build) writes a numbered
  session (P<number>) beside the test runs: every error and warning with its backtrace, what
  the game prints, slow frames, network events, zone changes and every message the player was
  shown. The first time each kind of issue happens (an error, a warning, a soldier fallen out
  of the world) it saves a state dump (every soldier, the AI's intent and target, the hot
  zone, the last log lines) and a screenshot. The folder ends PASS or FAIL; one that crashed
  stays RUNNING. The pause menu shows the session number. New suite `session_log`.

#### Changed

- `HotZoneDebug.readout(from)`: the hot-zone readout without the overlay, for the dumps.

### Wave 4B part 3: the hot zone; debugging rules (Captain's side, 2026-10-12)

#### Added

- **Hot zones** (16 km², `ZoneDef.generate_hot`): one enemy HQ, a comms site, 1-2 QRF bases,
  outposts, road checkpoints, villages, roaming patrol routes; campaign zones `ridge_hot` and
  `coast_hot`.
- **The enemy's alert** (`Alert`): the enemy only knows what its people see, hear and radio in,
  with report delays (a man killed first never reports), sound ranges (suppressed much
  shorter), check-ins, bodies found, a last known position that grows less certain; areas and
  the zone go normal, suspicious, alerted, engaged and cool down slowly. No meter on screen.
- **Pressure** (`Pressure`): points from what the squad does (firefights, kills, our blasts,
  wiped patrols, objectives, sites taken out, alarms; quiet decay; +1 per 30 min), halved with
  the comms mast down; tiers at 10/20/35/50.
- **The enemy's response** (`EnemyResponse`): roaming patrols (one goes to look at a report),
  patrols doubled and checkpoints closed when alerted or under pressure, the QRF from the
  nearest living QRF base when engaged (at once on standby, after a turnout if caught cold; a
  second at tier 2; none with every base gone), hunter teams at tier 3 (flank, track, smoke;
  fewer with officers dead), the HQ reinforcing its sites at tier 4. Nothing spawns in the
  squad's sight.
- **Looted enemy radio chatter** (`RadioChatter`): carry an enemy handheld radio to hear the
  enemy's net, until they switch frequencies.
- **Radio contracts** need a field radio (PRC-152) in the squad: "Radio for a contract" in your
  own menu.
- **Escape menu**: Resume, Return to Base (revert: back to just before deploying), Return to
  main menu, Quit.
- **Dev tools** (`DevTools.on()`: debug builds or `--dev`): hot-zone readout (Page Up), enemy
  clock skip (Page Down); test builds ship "Contractor (dev tools).bat".
- **Debugging rules** (Captain, `docs/debugging.md`, `CLAUDE.md`): every run keeps numbered
  logs by date with PASS/FAIL in the name; `tools/run_tests.sh` keeps them in
  `Contractor-test-logs` beside the main checkout.

#### Changed

- Hot zones drive reinforcement waves from the enemy's alert (no timer); waves head for the
  last known position.
- Debug instant extraction moved to Shift+End (End alone opens the board); K and Shift+End
  work behind `DevTools.on()`.

#### Fixed

- The HQ's watchtowers faced inward and garrison men faced anywhere: towers have parapets on
  their outer sides, posts face out, gate guards stand behind the sandbags facing the gate.

### Ragdolls, clean test sessions, clothing, intel fog (Captain's side, 2026-10-11 late)

#### Added

- **Ragdolls** (Captain): downed (unconscious) and dead bodies, AI and players, fall and lie
  as host-simulated ragdolls (`Ragdoll`: torso, head, thighs, shins, upper arms, forearms,
  anatomical joint limits), replicated as `CharacterModel.ragdoll_net` and kept by saves.
  Bodies rest on each other instead of clipping; a settled body freezes, so nothing shoves
  it; the living step over a body or pile up to 0.75 m. Hitboxes, wounds, blood and charges
  follow the ragdoll. Carried or dragged it goes; put down it falls again.
- **First-person arms**: your own forearms and hands on the weapon (there were none for
  anyone), mirrored for a left-handed shooter.
- **Clean test sessions** (Captain): the menu's play and test entries spawn players in their
  role's kit with one tidy row of spares (`CompoundLevel.CLEAN_LOOT`); the test contract
  starts fresh every time. The campaign keeps roster gear.
- **Roadmap**: item catalogue plan, dog tags (Captain: they count), and bases (Captain: no
  player-built FOB; friendly faction FOBs with portable company modules; replacement troops
  flown in from the LHD at a cost) in `docs/ChrisPlan_handoff.md`.

#### Changed

- **Civilians, HVTs and hostages wear plain clothes** (Captain): one flat colour, no camo,
  patch, belt or knee pads; HVT outfits by side, role, site, region and captivity
  (`PersonLook.outfit`). The chest box and the HVT head band are gone.
- **Briefing intel is never spot on** (Captain): estimates are off by what the intel's
  accuracy allows; under 60% accuracy quality reads as a word.
- **AI hold while a briefing is open**, so nobody dies before reading it.

#### Fixed

- A downed or dead body's capsule shoved itself out of anyone walking into it, and one going
  down beside another was pushed on top of it.
- Blood that landed on a body or item floated once that moved; it now sticks to it. Pools
  stop at edges.
- A downed (unconscious) player could crawl.

### Wave 4B part 2 follow-ups (Captain's side, 2026-10-11)

#### Added

- **HVT escorts** (Captain): command menu Action > "Escort that HVT" (look at him) puts the
  nearest of the selected squadmates on him, at most two (`Squad.order_escort`, SquadAI
  `Intent.ESCORT`); "Stop escorting" or any movement order takes them off. The first leads
  him along with the squad (waiting when he lags), the other stays close behind him; in
  contact both fight from beside him, between him and the threat. If he bolts they react
  after 0.6-1.6 s by skill (slower suppressed, not while pinned or blinded), run him down
  with weapons lowered and grab him within reach with a 55-80% chance per try; a fast
  enough runner still gets away. Downed, they carry him with the squad.
- **A wounded HVT is a medical priority**: one in the squad's hands (escorted, captive,
  hostage, down, carried) is a casualty for the squad's AI; his escorts treat him first
  with what they carry, and a free medic is pulled to him ahead of other casualties and
  takes over. Proposed numbers.
- **Garrisons sized from the true force** (Captain): a deployed contract's target module holds
  the contract's true enemy count (`ZoneLevel.garrison_size`, from `Contracts.enemy_force`), so
  an understated briefing really bites; other modules keep their 4. Extra posts stand beside
  the module's own at the first clear spot (a capsule check, `_extra_post`); a module that
  streamed in before the briefing is topped up when the contract goes live.
- **HVT capture without zip cuffs** (Captain: cuffs stay a base-shop buy, but the job must be
  doable without them): a hostile HVT who gave up (or was downed and carried) follows when led
  and counts when brought in uncuffed. An uncuffed one needs babysitting (`HvtAI._check_bolt`):
  nobody from the squad up and not pinned within 6 m for 4 s, and every 2 s he may take his
  surrender back and run (`PeopleLayer.server_take_back_surrender`), the odds climbing to 0.6
  over 12 s alone; a fight around him gives a small chance even when watched; the more it
  hurts the less he tries, and badly hurt he stays put. Cuffed HVTs never bolt. Proposed numbers.
- **Real names** for HVTs, hostages and civilians (`Names.mission_person`): HVTs from the
  target faction's nation (`factions.json` "nation"), hostages from mixed nationalities (US,
  UK, Canada and the region), civilians from the region's own people (`contracts.json` regions'
  "nation"); given names for the region and the wave 6 nations.

#### Changed

- The HVT capture brief explains the no-cuffs option. The placeholder name lists in
  `contracts.json` are gone.
- `docs/ChrisPlan_handoff.md`: suicide bombers and VBIEDs in wave 6 (VBIEDs after wave 5 V1);
  backlog: zip cuffs lootable in zones.

### Wave 4B part 2: missions in zones (Captain's side, 2026-10-11)

#### Added

- **Captain's first four mission types** (`data/contracts.json`, from
  `docs/mission_brainstorm.md`): **raid** (destroy a weapons cache or an AA gun; bonus: leave
  no fighter standing), **HVT capture** (a hostile HVT taken alive to extraction, 90 min clock;
  bonus: their phone), **hostage rescue** (a friendly hostage brought out, 75 min clock; bonus:
  clear the guards) and **intel grab** (a laptop or hard case carried out; bonus: the
  documents). They replace the four placeholders. Pay, enemy ranges and the clocks are Proposed.
- **Contracts in the generated zones** (seam 3): every contract zone is a world-scale
  `ZoneDef` generated from a fixed seed (`MissionRegistry.zone_def`), the same layout every
  visit, and a contract targets one of its modules (`module_id`); its objectives sit at that
  module's sites (`contracts.json` "modules": sites for the compound, outpost, village and
  checkpoint) wherever it stands in the zone (`Contracts.module_origin`). Accepting one deploys
  into its zone. A cache's voxel count can be `"auto"` (`ZoneModules.solid_voxels_in`).
- **New module art for raids**: an AA emplacement in the outpost (sandbag ring, twin-barrel
  steel gun: a grenade barely chips it) and crate caches in the village's plank shack and by
  the checkpoint's booth.
- **People reach the contract** (seam 5): when a contract goes live (`Contracts.contract_live`)
  the people layer puts its HVT or hostage (named, carrying their own intel), its intel pieces
  (each with its own intel id: only that piece counts), civilians going about their day in the
  zone's modules, and a delivery point at each landing zone. The People ledger feeds the
  contracts: deliveries, intel carried out (banked mid-zone), civilian casualties (once per
  civilian; the 8th voids), and a dead HVT or hostage (`People.hvt_lost`) fails its objective.
  An HVT brought to a landing zone the squad picked counts too.
- **Timed objectives**: "time_limit_min" on a mission type; the HUD shows the minutes left and
  the objective fails when the clock runs out.
- **Breaching charges, placed like Arma Reforger's** (Captain): Shift+G to the charge, G holds
  it up as a ghost lined up with the surface you look at (2.5 m), Fire sets it, G or RMB puts it
  away. It sticks to anything: the world, a person (it rides their body part) or a moving body
  (vehicles from wave 5 get `server_explosion`), the hook for suicide bombers on foot and in
  vehicles later. After the fuse (Proposed 10 s): a frag blast and a breaching carve; a raid
  target within 1 m is destroyed (`Charges`, `Objectives.server_charge_blast`).
- **Reinforcements sized from the true force** (seam 7): `Contracts.reinforcement_tuning`
  (first wave sooner and waves bigger the higher the true rating, living hostiles capped at
  the true count plus 8, the waves' skill from the true quality), started with the contract.
  In a zone they come in at the terrain's edge nearest the squad but at least 350 m out
  (`ZoneLevel.reinforcement_edge`).
- **The briefing** marks objectives at their module and what intel knows of the enemy there.
- `missions` test suite (21 suites now).

#### Changed

- The contracts test registers its own compound-clearing type for the clear-area checks.
- `breaching_charge` fuse 5 s -> 10 s (Proposed).

### Female soldiers (Captain, 2026-10-11)

#### Added

- **A female body for soldiers** (`scripts/art/voxel_art.gd`, `_head_f`, `_torso_f`,
  `_upper_arm_f`, `_forearm_f`, `_leg_f`, `_thigh_f`, `_shin_f`): the same Stormworks
  low-poly style, on the same frames and pivots as the male parts, so animations, plates,
  carriers, helmets, pouches and held weapons fit. Her own proportions, loosely after real
  averages: drawn at 93% of the male model (about 1.68 m to 1.80 m), with gear and hitboxes
  scaling with her, and her own shoulder joints (`CharacterModel.FEMALE_SCALE`, `FEMALE_SHOULDER`; see
  Changed below). Narrower shoulders and slimmer
  deltoids and arms, a narrower waist over fuller hips (0.36 m) with a seat, a chest under a carrier that
  rides forward over it (see Changed below), slimmer legs, smaller hands and boots, and a smaller
  head with a softer jaw, thin brows, lashes, lips and the hair in a low bun under the
  helmet's rim, with hair framing the face.
- **Choosing the body:** `CharacterModel.body` ("male", the default, or "female"),
  `Soldier.body`, and an optional `"body"` in `CompoundLevel.spawn_soldier` data (it rides
  the spawn data, so every peer builds the same body). `Soldier.body_record` saves it, so a
  dead soldier's body keeps it. `VoxelArt.body_part(part, body)` names the model
  ("torso" or "torso_f"). Players can't pick it yet (no menu option).
  Male models are unchanged, byte for byte.
- **Who's a woman follows the force's norms** (`scripts/ai/demographics.gd`, Captain's call): an AI
  soldier's chance follows their nationality and role. A medic is at their nation's overall
  share and every other squad role at 0.3 of it, since women are fewer in combat arms. Overall
  shares: US 17.7% (DoD 2023), Canada 16.3% (DND 2024), UK 11.9% (MOD 2024), Russia about 4%,
  China about 4.5%. Iran (women only in medical posts) and insurgent cells: none in field
  squads. The PMC follows each contractor's nation. A US rifleman is a woman about 5% of the
  time, a US medic about 18%. Russian surnames take the feminine form (Ivanova).

#### Changed

- **Her own shoulders** (Captain: "their own proper shoulder value"): `CharacterModel.FEMALE_SHOULDER`
  (0.20 m out, 1.5 cm lower than his 0.25 m, replacing `FEMALE_SHOULDER_X` 0.225 m) and
  `CharacterModel.shoulder_of(body)`. Her arms hang against a narrower ribcage without
  passing into it; rounded deltoids cap the joint and the shoulder line slopes down from the
  neck instead of the male square shelf. The kneel/reach solver (`reach_pose`) uses her
  shoulder too.
- **Her chest higher and fuller** (Captain: "too low and too small", then "reduce ... or make
  the carrier fit like irl"): two low-poly lobes high on the chest, 0.135 m in front of the spine
  (the male chest: 0.11 m).
- **Carriers fitted to her like real ones** (Captain's photo refs: "the carrier conforms to the
  body while the plate sits inside"): she wears `VoxelArt._vest(tier, torso_fc, true)`
  ("vest_f:<tier>"): the cummerbund is her own torso shape plus padding, the back panel sits
  `FEMALE_CARRIER_BACK` (2 cm) further in against her slimmer back, the heavy rig's side
  pockets sit in at her sides (`carrier_side_inset`). The front panel ("vest_f_front:<tier>")
  sits flat `FEMALE_CARRIER_FRONT_OUT` (1 cm) further out, padded inside down to her chest and
  belly (no gap under it), with cummerbund wings from its edges round her sides to the rear
  panel. Under a carrier her bust is held flat and pushed out to the sides ("torso_fc",
  `CharacterModel.set_carrier_worn`, which GearRig calls). Everything on a panel goes with it
  (`GearRig.carrier_fit(face)`): plates, MOLLE pouches by their face, name tape and slung rifle
  (front), pack and pack straps. Male carriers are the same as `art/carrier-fit`'s.
- **Her hips and waist** (Captain: "more natural instead of like a Mii"): one smooth curve,
  widest at the hip joints (0.35 m) and easing in to a 0.27 m waist about 20 cm up (it pinched
  from 0.35 to 0.26 m over 10 cm); the seat is broad and flatter across the hips, setting out
  from the small of the back, instead of a ball.
- **Medical voxel wounds on her body:** `BodyVolume.pivot_at(part, body)` puts her arm shapes
  at her shoulders (hits were judged, and blood drawn, 2.5 cm off at the male joint); the
  host builds both bodies' shapes at start (`BodyVolume.warm(["", "female"])`). Wounds test:
  her upper arm is judged at her own shoulder.

### Respawns paid cash first, then the support budget; who fields the US heavy kit (Captain, 2026-10-11)

#### Changed

- **Bought respawns** (past the deployment's free ones) cost more each time (`prices.json`
  "respawn_rise": $1,000, $1,500, $2,000...) and are paid from **cash first, then the
  deployed contract's support budget**, then on credit (`BaseHub.server_count_respawn`).
- Plans: the AH-1Z, MRAPs, Bradley and Abrams are fielded by the US and by close allies that
  operate those exports (the UK and Canada: MRAPs only). Reputation tiers, ripple, decay and
  allied troops point at the mission brainstorm, where they're decided.

### The mission brainstorm in the repo (Captain, 2026-10-11)

#### Added

- `docs/mission_brainstorm.md`: Captain's mission brainstorm (Oct 10), exported from claude.ai.
  Wave 4B part 2 takes its mission types and debrief from it. The design doc and plans link it.

### Net test smoke check and the voxel smoke roadmap (Captain's side, 2026-10-11)

#### Fixed

- **Net test:** the purple smoke the host throws before the client joins now starts
  `SMOKE_AGE_S` (3 s) old and the client checks its copy is at least that old. It used to
  check for over 2 s and failed whenever the client joined quickly (1.6 s), though the copy
  was right.

#### Changed

- `docs/ChrisPlan_handoff.md`: CS2-style voxel smoke on the roadmap (wave 7, S5).

### Wave 4B part 1: the mission loop wired end to end (Captain's side, 2026-10-11)

#### Changed

- **One bank:** the base runs on the `Economy` autoload (`BaseEconomy` is a thin adapter; the
  stand-in cash is gone). The base terminal's shop is `Economy.server_buy` into the armory
  stash (`purchase_sink`), salvage and what's brought out land in the stash (`stash_sink`), the
  respawn price is `prices.json` "respawn".
- **One clock:** `BaseHub.day()` is `Economy.day()`. Resting, deployments and travel move it
  through `Economy.advance_days`; the roster's recovery and the hiring board follow
  `day_advanced`; the roster's wages are the weekly bill (`Economy.wages_provider`) with base
  upkeep and loans. A deployment's days pass once. Older saves give their base day way to the
  economy's.
- **Board -> base -> zone:** accepting a contract starts its prep at the base
  (`BaseHub.begin_prep_contract`; "Prepare deployment" on the board and "Prep" on the base
  screen pick another held one). Deploying takes the squad into the zone, where the briefing
  opens for everyone on the zone's map; its start makes the contract live, moves the squad to
  the insertion point and opens extraction.
- **One end of a deployment:** extraction's report settles it once
  (`BaseHub.end_deployment`, an `Extraction.END_GROUP` handler): the debrief (pay, clawback,
  fines, reputation, days), then the roster (MIA, recovery contracts, gear home), then everyone
  back at the base. People bring their own gear home; bodies carried in and items set down at
  the point go to the stash.
- **Clawback terms** (Captain): each contract states what a void does to the advance: kept
  (none), prorated (the share of required objectives not done is given back) or returned
  (full). Fixers' jobs keep it, the safe job returns it, the rest are rolled; a lenient client
  pays less (`contracts.json` "clawback_terms", replacing `void_claws_back_advance`). Shown on
  the board, in the briefing and in the debrief.
- The board in a campaign has no debug deploy, end or reset buttons.

#### Added

- **Recovery contracts:** a squadmate left behind alive puts a recovery contract on the board
  (`Contracts.server_add_recovery`: no pay, `recovery_offer_days`). Deployed on it, they wait
  where they were left, join the player who reaches them (`BaseHub.FOUND_M`) and come home
  recovered if they're inside the extraction point; anything else writes them off.
- `Contracts.contract_accepted`, `contract_closed` (with `EXPIRED` for an offer that ran out),
  `server_abandon_deployment` (a save made mid-deployment); objective templates may carry
  their own site (`"params"`).
- Tests: base "The loop" (board -> prep -> briefing -> extraction -> debrief -> base, and a
  recovery end to end); contracts: clawback terms.

### Carriers fit the body that wears them (Captain, 2026-10-11)

#### Changed

- **Plate carriers are cinched to the wearer** (Captain: "make the plate carrier fit more like
  it would irl"): the cummerbund is the wearer's own torso shape plus `CUMMERBUND_PAD` of
  webbing and padding (1.5 cm medium, 2.5 cm heavy), so it takes in at the waist and lies on
  the body instead of standing off it as a box; the light rig's straps lie on the body; the
  heavy rig's side plate pockets reach in to the cummerbund (the plates stay where they were).
  `VoxelArt._vest(tier, torso)` takes the wearer's torso spec (the male one by default), so
  another body shape gets a carrier fitted to it.

### Medical voxel wounds on the current dev (merge)

#### Changed

- **World test:** the doorway shot aims at the pelvis; at 0.6 m on the man's centre line it
  passed between his legs, which hits on the body's real shape (BodyVolume) now allow.

### A hired squadmate is one person (Captain, 2026-10-11; wave 4B groundwork)

#### Changed

- **Hiring rolls the whole person once:** each contractor on the board has a first name,
  a surname, a nationality (US, UK or Canada by weight), a shooting hand (11% left) and a body
  type (`Names.person`), shown on the board and the roster ("Brandon Stewart, CA, right-handed").
  The roster keeps it, and **every deployment spawns that same person**: their surname on the
  name tape, their nationality and their hand (`Roster.identity`, merged into the spawn data by
  `BaseHub.server_spawn_roster_squadmate`). Before, the board's name and the name tape were
  rolled separately and didn't match. The body type is always male on `dev`; the female-model
  branch decides it in `Names.body_for`.
- **No two name tapes in the company match:** a new hire whose surname is taken gets another
  from their nationality (`Roster.unique_surname`).
- **Older saves:** a member hired before this keeps their roster name ("Dale Okafor" -> OKAFOR
  on the tape) and gets a nationality and hand once, seeded by their callsign
  (`Roster.ensure_identity`).
- **Bodies keep the person:** a body's record saves and restores the name tape, nationality and
  hand (`Soldier.body_record`, `CompoundLevel._make_body`).
- **Tests:** the base suite checks the board, the hire, a clashing surname, an older save, the
  deployed squad, a fallen squadmate's body and a second deployment.
### The test runner can't pass a broken suite any more (audit L5-01)

#### Fixed

- **`tools/run_tests.sh`:** a suite passes only if it exits 0, prints its `<NAME> TEST PASSED` line
  and logs no `SCRIPT ERROR`. Before, a script that failed to compile (a parse error) or crashed
  mid-test could read as passed, or hang the run forever. Each process now has a timeout
  (`SUITE_TIMEOUT`, default 480 s) and fails as hung past it; the import must succeed; the net
  and world hosts are judged too, with their output kept.
- **`tools/test_runner_check.sh` (new):** checks the runner against a fake engine: a pass
  passes; a failure, a script error with exit 0, a missing summary, a hang and a failed import
  fail. CI runs it as its own job, and the rerun-on-failure step has a timeout now.
### A squadmate that gives up its slot leaves what it was handed (audit L1-03)

#### Fixed

- **Outside the campaign, an AI whose slot a player takes drops what it holds beyond the kit it
  spawned with:** items players handed it, what it scavenged, an objective item, in a pile at
  its feet with their state (part-used magazines, damaged armor). Its own kit goes with it, so
  a join doesn't hand out free gear. Before, it all vanished. (In the campaign a roster member
  already keeps everything.) Stacks unlike its starting kit go first, so a handed-over
  7-round magazine is the one left, not one of its own full ones.
- **Test:** roles suite (salvage and a part-used magazine left behind, no kit items).

### Medical: impact pain is eased by morphine (audit L3-01 check)

#### Added

- **Medical test:** pain from a round stopped by armor (impact, no wound) asks for morphine,
  a dose eases it well beyond its own fading, no second dose is asked for once there's nothing
  left to ease, and light impact pain uses none. The audit's finding (a kit used up on impact
  pain it couldn't treat) was about the old stopgap kit; wave 3's morphine already treats it.

### Late joiners, bad input, reloads, sprinting, fire cadence and the menu (audit L2-01, L2-02, L3-02, L4-02, L6-01, L8-01, L10-01)

#### Fixed

- **Late joiners see smoke already out,** at its age (`CompoundLevel._send_smoke_to`); before,
  the AI could hide in a cloud they couldn't see.
- **Late joiners see a carried or dragged body as not solid,** from the replicated carry state.
- **Bad coordinates are refused:** a shot, throw or squad order from a NaN or infinite point, or
  with no direction, is turned down before a round or grenade is spent (`Soldier.usable_point`,
  `usable_direction`); map markers, extraction points and reports check theirs too.
- **A reload started before dying no longer finishes on the respawn rifle.**
- **No sprint without room to stand tall:** under a low roof a low stance stays at walking
  speed and uses no stamina.
- **Shots bunched by the network still count:** the host's fire gate lets its schedule run up
  to 0.15 s behind (`Soldier.FIRE_BUNCH_S`), so correctly paced shots aren't dropped under
  jitter, while a flood still fires at the weapon's rate (2 at once at most after a pause).
- **Main menu:** centred in the window, and it scrolls in a small window instead of running
  off it.
- **Tests:** gameplay (bad input with a control shot, reload across a death, fire cadence),
  net (smoke and a dragged body for a late joiner), movement (no sprint under a low roof).

### Saves can't lose progress (audit L1-01, L1-05)

#### Fixed

- **Partly taken loot stays partly taken:** taking some of a level-placed stack (no room for the
  rest) now saves what's left; before, a reload brought back the full stack.
- **Saves go through a checked temporary file** (`GameState.write_safely`): the zone and the
  campaign are written to `<save>.tmp`, read back, then swapped in, with the previous save
  kept as `<save>.bak`. A save that is cut off or unreadable loads its backup instead.
- **A save is checked before it replaces anything** (`GameState.read_save`): a section of the
  wrong type refuses the whole save; a single bad record (an unknown item, a position that
  isn't three finite numbers, a count below 1, a broken body) is skipped with a warning and
  the rest loads. Before, such a save could leave the host without a player.
- **Tests:** the gameplay suite checks the partly taken stack across a reload, the backup, the
  fallback from a cut-off save, bad records and a wrong-typed section.

### AI soldiers have names, on name tapes (Captain, 2026-10-11)

#### Added

- **Names:** every AI soldier gets a surname and a nationality (`scripts/ai/names.gd`), and
  is called by it everywhere a callsign used to show: callouts ("Martinez: Reloading!",
  "Man down! Thomas is down"), the HUD squad list, the command menu, AI status lines and
  the interaction menu. The node keeps its callsign (Alpha, Bravo...) inside the code.
  - **Your PMC** hires US, UK and Canadian contractors (60/25/15). Each pool is that
    country's most common surnames.
  - **The insurgents** use regional surnames. Russian, Chinese and Iranian pools are ready
    for the faction wave.
  - **Names are stable and unique:** a callsign keeps its name, and no two soldiers on a
    side share one. A recruit who replaces a fallen squadmate gets a name of their own.
- **Name tapes:** the surname, in capitals, on a tan tape on the carrier's loop panel. It
  replaces the flag patch there.

### Weapon holds, and left- or right-handed shooters (Captain, 2026-10-11)

#### Added

- **Left-handed shooters:**
  - **Players** pick "You shoot: Right-handed / Left-handed" on the main menu. The pick is
    saved between sessions (`user://settings.cfg`) and sent to the host on join, like the role.
  - **AI soldiers** are left-handed at the real rate for men, 11% (about 10.6% of people
    overall, men about 1.23 times as likely as women; `scripts/actors/handedness.gd` has the
    sources). Each roll is seeded by the soldier's name, so a callsign keeps its shoulder.
  - **What mirrors:** the rifle shoulder, the firing and support hands, the sling, the
    holster, the draw, and your first-person hip view.
- **Everyone sees you shoulder your weapon:** aiming (`Soldier.is_aiming`) is replicated.

#### Fixed

- **Weapon holds (third person):**
  - **Stock in the shoulder:** a rifle's butt sits in the firing shoulder's pocket. Aiming,
    it points straight out and the head dips onto the optic.
  - **At the ready,** the stock stays in the shoulder and the muzzle dips 30 degrees, in
    across the body. Before, the rifle floated in front of the chest with its stock inside
    the body.
  - **Hands on the weapon:** the support shoulder comes forward as a shooter's does, and the
    support hand takes the handguard within reach (up to 0.52 m from the butt). Both hands
    land on the weapon in every hold.
  - **Pistols** are pushed out two-handed at the eye line when aiming, and held low in front
    of the chest at the ready.
  - **Slung:** the rifle hangs diagonally across the front of the carrier, clear of the
    pouches, with the stock under the firing-side armpit and the muzzle at the other thigh.
    Before, it hung straight down beside the arm.
  - **Bladed stance, no floating shoulder:** holding a rifle at the ready or aiming
    (standing or crouched), the upper body turns 23 degrees (`CharacterModel.BLADE`, 0.4 rad)
    about its own up axis, support shoulder forward, as a shooter stands; the head and the
    weapon turn back by as much, so they still face where the soldier looks. The hitboxes,
    plates and carrier turn with the body. The support shoulder joint now comes forward only
    a little, inside the deltoid (`SUPPORT_REACH` 0.04 in, 0.06 forward). Before, it moved
    14 cm forward and floated in front of the torso. The shoulder pockets turn with the
    chest, so the stock stays in the shoulder and both hands stay on the weapon. Treating
    yourself takes the wound from the squared-up body, and no longer turns you towards
    your own arm.
  - **Slung rifle lies flat:** on its sling the rifle now lies on its side against the
    chest, ejection port out and the magazine pointing down towards the firing-side hip,
    4 cm closer to the carrier. Before, the optic stuck straight out and the magazine
    pointed into the chest.
- **Net test:** the remote treatment check waits up to 1 s for the treat animation to
  replicate (action_net comes on its own sync, after the vitals), instead of checking in the
  same frame. It failed now and then under load.
- **Tests after the dev merge:** the people, base and world suites looked soldiers up by
  callsign where the game now shows the name on the tape (`display_name()`); they pass that
  name in or read it. The map suite clears the compound's hostiles before its clients join:
  an unarmoured client shot down while standing about left a body the extraction report counted.

### Stormworks-style character models (Captain, 2026-10-11)

#### Changed

- **Soldiers rebuilt in a low-poly Stormworks style, still in voxels** (`scripts/art/voxel_art.gd`):
  body parts are lofts with flat faces and 45-degree bevelled edges, written in centimetres
  and built in 0.5 cm voxels, on the same joints as before, so animations, helmets, plates,
  pouches and held weapons fit unchanged. The trunk now reaches down to the crotch (the hips
  10 cm below the hip joints) with the belt at the waist, so the legs show from where they
  do on a real body. A boxy head with a flat face: eyes, brows, nose, mouth and ears.
- **Camouflage by faction:** MultiCam (soft brushed blotches, a few dark flecks), woodland
  (blotches with black branches), desert (broad drifts) and urban (grey woodland),
  domain-warped so the shapes flow.
- **Plate carriers enclose their plates:** rebuilt in 1 cm voxels with a fabric pocket round
  each plate and a lip over its edges. A plate in its pocket takes the carrier's fabric
  colour (`VoxelArmor.cover`); chips and holes still show the plate under the torn cover.
  The heavy carrier has side-plate pockets, a collar and a groin flap.
- **Captain's first look:**
  - **Chin:** the jaw is now a 45-degree chamfer under a straight face. Uneven slopes stepped
    unevenly at 0.5 cm and showed as bands across the chin and face.
  - **Shoulders:** the torso has deltoids. Above the chest they flare out at 45 degrees to
    0.26 m, over the shoulder joints, and the trapezius runs flat in to the neck. The upper
    arms taper into them, so the arms hang out from under the shoulders and turn under them.
    The arms used to hang 4 cm clear of a narrow trunk, like separate columns.
  - **Plate carriers less blocky:**
    - **Shape:** the pockets have bevelled edges and a chamfered top, and the cummerbund takes
      in at the waist.
    - **Shoulders:** the shoulder straps are padded pads that arch over the deltoids, where
      they used to be solid blocks.
    - **Details:** PALS webbing rows across the front and back panels, seams round the plate
      window, a loop panel with a flag patch at the top of the front, and a drag handle at the
      top of the back.
    - **Backpack straps:** a worn pack's padded straps come over the shoulders and down the
      front edges of the plate pocket, with a sternum strap.
  - **Front pouches** sit on what's behind them: on the plate face (in the pocket's window),
    or on the cummerbund beside the pocket. They used to float 2 to 4 cm off it. The medium
    carrier's TQ holder moved out to the pocket's edge.

### Wave 4A of the build plan: the mission loop, first half (cghath, 2026-10-11)

Five parts built in parallel, ported onto Captain's wave 3, reviewed, and integrated. The loop
isn't wired end to end yet (wave 4B): each part has its own entry point on the main menu.
Mission types are placeholders (clear a compound, recover an HVT, retrieve intel, destroy a
cache) until Captain's mission types land. Values the design doc doesn't fix are "Proposed:".

#### Added

- **Hits land on the body's real shape** (`scripts/combat/wounds/body_volume.gd`). A
  hitbox box is now only the first test: the round is marched through that part's 0.5 cm
  voxels (the character model, in the rest pose), so a round between the legs or past a
  wrist that only crosses the box flies on, and one that hits enters where the body starts.
  The wound channel runs as far as the body does along the round (a forearm short, a chest
  the whole trunk) instead of to the edge of the box. Built once when hosting (about 0.7 s).
- **Wounds show where they are.** Each wound keeps the rest-pose point a round went in at
  ("at") and, when it went through, came out at ("out"), replicated with the wound list (to
  half a centimetre). `WoundMarks` (`scripts/player/wound_marks.gd`) draws an entry hole and a
  bigger exit hole on the bone of the part that was hit, and a dressing once it's treated.
  The marks follow `Vitals.changed`, so they appear within `NET_INTERVAL_S` (0.5 s) of the hit.
- **Voxel blood.** Holes have a dark core and a torn red rim (ragged at an exit). While a
  wound bleeds (its replicated rate; internal bleeding stays inside, a tourniquet slows it,
  treatment stops it), blood soaks out round it and runs down the skin with gravity in 1 cm
  voxels laid on the body shape (`BodyVolume.surface`), drips off the lowest point and
  pools on the ground, spreading out as drops land. A round that goes through throws a spray
  out of the exit onto the ground behind. Treated, the stain dries dark and a dressing wraps
  the limb (a pad on the trunk or head). Cosmetic and local: no extra network traffic. One
  MultiMesh per bone, and one each for drips and the pool. The pool spills outward from
  where the first drip landed, so it shows past a body lying in it; spatter leaves specks.
- **Body types for hit shapes and blood.** `BodyVolume` keeps a shape per body type
  (`body_of` reads `CharacterModel.body`; `model_of` names the female parts "<part>_f"), so
  hits and blood follow the female body from the `art/female-model` side project once it
  merges. Male only until then.
- **World scale.** A contract zone is a seeded 2-4 km2 terrain (rolling hills, haze, distant
  terrain at lower detail) with hand-built voxel modules placed on it: the compound, small
  outposts (HESCO ring, concrete bunker, wooden watchtower), a village block of four houses in
  mixed materials, and a road checkpoint. Modules load as full 10 cm voxels within 260 m and
  unload past 340 m; a stand-in shows them up to 2.5 km away. Each has its own loot, a hostile
  garrison in buddy pairs, voxel edits and bodies, all saved with the zone. Shooting, armor,
  frags, first aid and looting work inside modules. AI navigation bakes in the background
  around players and soldiers in a fight. Main menu: **Host test zone (2 km, world scale)**,
  or `--zone [id]`.
- **Contracts and economy.** A seeded contract board (always one low-risk job; fixers'
  special jobs at enough reputation), contract zones and hot zones, a 1-5 difficulty rating
  that can understate the threat (more often with poor intel), MW5-style negotiation of pay,
  salvage share, support budget and advance (30%, kept on failure), renegotiate or abort once
  the real threat shows, up to 4 contracts held, lapsed contracts cost reputation. Cash with
  a ledger, per-faction reputation (numbers only until wave 6), a campaign clock in days with
  weekly wages and upkeep, and a safety-floor loan. Objectives (clear an area, carry an item
  out, deliver an HVT, destroy a cache) shown in the HUD. A debrief: pay and bonuses, civilian
  fines (the 8th casualty voids the contracts), MW5-style salvage picks, what was carried out
  (MOLLE pouches and their contents counted), casualties, reputation, intel turned in or sold.
  A shop for gear, repairs, medical supplies and support calls. Main menu: **Contract board
  (offline)**.
- **People.** Civilians who go about their routines, flee and hide from gunfire and never
  fight; casualties caused by the squad count against the contract, others don't, and AI
  won't shoot through a civilian. Hostile HVTs try to expose the squad and run until
  zip-cuffed; friendly HVTs follow; captives can be led, stopped, sent to cover, searched and
  carried (the waist body point). Intel (laptop, phone, documents) on officers and at sites,
  counted once carried out; enemy positions reported by radio bank at once. Badly hurt,
  isolated hostiles may surrender. A main menu checkbox puts people in the compound.
- **Base hub and roster.** A walkable FOB with an armory (the company stash; carriers keep
  their MOLLE pouches and contents), a motor pool (for wave 5), a medbay, a hiring board and a
  shop terminal. Squadmates are persistent people: name, role, skills (aim, nerve, medical,
  movement) that grow with experience along with their wage, their own gear, history and
  injuries (broken bones, burns, blast lung, heavy blood loss mean days out; the medbay
  shortens it for money). A rotating hiring pool; no fixed starting squad. Prep before a
  deployment: kit up, assign squadmates and roles, buy supplies, deploy. An AI squadmate left
  behind alive goes MIA; the respawn pool is 4 free in a contract zone, 8 in a hot zone, then
  bought. Main menu: **Campaign: host at the base (FOB)**; Join follows the host there.
- **Map, briefing, extraction.** **M** opens a map with an Arma-style grid and references,
  zoom and pan, your squad's positions, shared markers and lines, intel enemy positions,
  objectives and extraction points (every player and late joiner sees them). A briefing on
  the map before a deployment: contract, objectives, known enemies, plan marks, insertion
  point, supports (a list until wave 5), ready-up. Extraction at a landing zone, a grid
  reference or a purple smoke, once every living player and the AI you bring are inside, the
  host confirms and a 10 s countdown runs; it reports who and what got out. A reinforcement
  timer sends hostile waves from beyond the map edge, sooner and bigger over time, with no
  on-screen timer. Main menu: **Play the test contract (briefing, extraction)**.
- `Campaign`, `Economy`, `Contracts` and `People` autoloads; one save per campaign.
- Tests: world, contracts, people, base and map suites (20 in all, all in CI).

#### Fixed

- One join handshake for every kind of level: a client joining a hosted zone, a campaign at
  the base or a deployment now loads the host's level before anything replicates.
- A joining client's player starts at the gate or insertion point instead of the middle of the
  level, and loading magazines right after joining no longer stops with "you moved".
### Scavenging review fixes

#### Fixed

- **An AI that picks up a rifle from a body now fights with it.** Unequipping his own dry
  rifle switched him to his sidearm, and nothing switched him back: a marksman kept firing
  9mm with a loaded MK18 on his back.
- **Medical restock counts the whole basic load.** A tourniquet in the holder and one in the
  IFAK are a basic load of two. Each was compared on its own against everything he carried,
  so a rifleman down to one tourniquet wanted none.
- **A dry M4 takes the body's 5.56 magazines, even part-used ones, instead of the MK18**, as
  the scavenging rules say. Part-used magazines scored lower than the rifle swap.
- **A stowed pouch or carrier takes the room its contents fill.** Only the empty pouch or
  carrier counted, so a full sustainment pouch (2 L) went into a pack as 1 L, and a carrier
  with every pouch loaded as a bare 8 L. An empty pouch still folds down to its own size.
- **The medium carrier's knife no longer clips into the first mag pouch:** its point moved up
  2 cm, level with the heavy carrier's.
- **The IFAK and radio pouches are no longer inside the upper arm.** Their side points on the
  medium and heavy carriers moved 13 cm rearward, clear of the arm, the slung rifle and the
  pack. With the arms hanging (downed, dead, unarmed, the inventory preview) the arm used to
  hide the IFAK completely.
- **A looter who goes down lets go of the body.** A squadmate sent to carry that body waited
  beside it for good.
- **An AI can't get stuck walking to a body.** With a player standing still between them, it
  pushed into the player for good. Like a medic reaching a casualty, it now sidesteps after
  1.5 s without getting closer and leaves the body for a while after 12 s.
- **"Scavenge that body" works past 40 m from the leader.** The order went out, then was
  quietly dropped by the leash that should only hold back scavenging on his own initiative.
- **Drag and drop works in the inventory screen.** Pressing a tile rebuilt every tile, which
  freed the one under the mouse, so Godot never started the drag. A click now only restyles
  the selection.
- **A right-click menu won't act on the wrong item.** If what it was opened on moves or goes
  while it's open (a reload, loading magazines), choosing an action does nothing.
- The logistics test's breach check waits (up to 3 s) for the navigation map to take the
  rebaked chunks, instead of a fixed 3 frames that a slower machine (CI) can miss.
- The scavenge tests now check that a looter lets go of the body, with two squadmates
  wanting the same body, and that the leash spares an order.

#### Changed

- **Grenade and binocular pouches go on the chest, where they can be seen.** The medium
  carrier has two new Chest points on the upper front; grenade and binocular pouches take them
  first, a grenade pouch then a free mag point. Every back point sits inside the pack, so the
  grenadier's grenades and the team leader's and marksman's binoculars were hidden. GP and
  sustainment pouches stay on the back.

### Wave 4 groundwork and a spall pain fix (cghath, 2026-10-11)

#### Added

- `Campaign` autoload (`autoload/campaign.gd`): the host-owned campaign save
  (`user://saves/campaign_01.json`) that the wave 4 mission loop keeps its money, contracts
  and roster in, one section per part. `CompoundLevel.map_area()` gives the map its playable
  area. Nothing uses either yet, so play is unchanged.

#### Fixed

- Spall from a steel plate stop now counts its pain inside the plate stops' capped budget
  (`PLATE_IMPACT_MAX`) instead of on top of it, so plate hits alone, spall included, never
  knock a healthy soldier out. Six 5.56 plate stops at 50 m plus two face spall wounds could
  reach 0.88 pain and drop someone (armor suite, "6 plate hits" check).

### AI scavenging, visible tourniquets and IFAKs, and looting MOLLE pouches (Captain, 2026-10-11)

#### Added

- **AI scavenging.** Out of contact, an AI soldier short of something goes through a nearby
  dead body and takes what it needs, one item at a time, each pick taking its time (a pouch
  1.5 s, a pack 4 s, a plate swap 8 s). Squadmates and enemies follow the same rules
  (`scripts/ai/scavenge.gd`):
  - **Ammunition first:** only magazines his own weapon takes, up to his role kit's basic
    load. A marksman leaves 5.56 magazines alone.
  - **Medical items** his kit lacks, counting what's left in his IFAK. Tourniquets, gauze,
    chest seals and bandages come before the rest, and a loose item before a whole kit.
  - **Then grenades and smokes, and anything else his kit lost** (a team leader's radio).
    Intel, once it exists, always comes.
  - **Armor only well out of contact:** a plate that clearly protects more than his own (his
    is cracked through or rated lower) and fits his carrier, or a helmet. His old piece stays
    on the body.
  - **Another rifle only when his own has no rounds left anywhere** and the body's has some.
    A dry M4 takes the MK18's magazines instead, since they fit.
  - **Never past 35 kg of load** (armor swaps and intel aside), and never bulky items, spare
    carriers or packs. The rest stays for players.
  - **One soldier per body.** A squadmate about to carry a fallen friend's body waits while
    someone cross-loads from it. A dead player's body is never touched: that gear waits for
    its player under the gear marker.
  - **Contact stops it** at once, and the item in progress stays on the body.
  - **Command menu, 6 Action:** "Scavenge that body" sends the nearest selected squadmate to
    the body under the crosshair. "Scavenge freely" and "Don't scavenge" switch it on or off.
  - The HUD shows "Going to the body" and "Searching the body", and he calls out "Checking
    the body".
- **Tourniquet holder** (`pouch_tq`): an open-top MOLLE holder for one tourniquet, on a new
  Tourniquet point on every carrier, on the front mag row on the support-hand side. Every
  role's base kit now carries one with a tourniquet in it, on top of the one in the IFAK
  (one on the kit, one in the kit). You can see the tourniquet in it (black band, windlass
  across the top, red tab).
- A full IFAK pouch shows its red pull tabs.
- A new scavenge test suite (31 checks), run by `tools/run_tests.sh`.
- **CI:** GitHub Actions runs all fifteen suites on every push and pull request, one job per
  suite, on the Linux editor of the Voxel Tools v1.7 release (`.github/workflows/tests.yml`).

#### Changed

- The IFAK pouch's Medical point moved from the back of the medium and heavy carriers, where
  the pack hid it, to the right side. The utility pouch that was there went to the back. On
  the medium and heavy carriers the knife moved up to the chest to make room for the
  tourniquet.
- A pouch that names an item (the tourniquet holder for a tourniquet) is filled before one
  that takes the item's whole type (the IFAK pouch).

#### Fixed

- **Looting bodies with MOLLE pouches:** the Loot list now shows what's on the carrier and
  in its pouches, and you can take those one by one. Before, magazines in pouches weren't
  listed at all. Loot all hands a carrier over with its pouches empty and their contents as
  separate items, so the magazines land in your own pouches instead of being buried in a
  spare carrier in your pack.

### Captain's wave 3 playtest fix: letting go of a body

#### Fixed

- **No way to release a body you were dragging** (it only showed on self-interaction):
  Left Ctrl on the body you're dragging or carrying now shows its point with Release (or
  Put down) first, and **G** lets go of it too, since your hands are full and there's
  nothing to throw. Release also stays on your own waist point (Left Ctrl + Left Alt).

### Wave 3, part 6: medical technique animations

#### Added

- Every treatment has its own hand technique, on the action-animation system, for every
  peer, on someone else and, where allowed, on yourself:
  - **Bandages and burn dressings** wrap round the limb (ACE-style pressure wrapping) while
    the other hand holds the end.
  - **Gauze** is packed in while the other hand presses beside it.
  - **Tourniquets** go on high and tight (12 cm above the wound, towards the trunk): strap
    round, windlass turns, then into the clip.
  - **Splints** are worked along the limb.
  - **Chest seals** have their backing peeled, then go on and are smoothed out.
  - **The decompression needle** goes in slowly at the second intercostal space.
  - **Injectors** (morphine, epinephrine, atropine, adenosine) are wound up, jabbed home and
    held.
  - **IVs**, in an arm or a leg, go in along the vein with the skin stretched, then are
    taped. The **IO** is pressed hard into the sternum.
  - **CPR** is compressions 5 cm deep at about 110 a minute, hands stacked. The
    **defibrillator** gets its pads on, then hands come off clear for the shock.
  - **The surgery kit** is fine two-handed work.
  - **Bags** are held up high with a hand at the line.
  - **Blankets** are swept and tucked round the body, and **the NPA** goes in the nostril
    with the head tilted.

### Wave 3, part 5: body interaction points

#### Changed

- **ACE3-style body points.** Looking at a squadmate (down or standing) with Left Ctrl now
  shows points on their head, chest, left and right arm and left and right leg. They sit on
  the body's hitboxes, so they follow it standing or lying down. Each point offers a check
  of that part, then the treatments that go there: a tourniquet on the leg it's for, the
  NPA on the head, the IO, seals, needle, CPR and the defibrillator on the chest. A general
  point at the waist has carry, drag, give item and check condition. Self-interaction
  (Left Ctrl + Left Alt) lays the same points out like a body around the screen centre,
  with check wounds and the rest at the waist. Enemies, the dead, dummies and items keep a
  single point.
- **IVs in the legs:** an IV can go in either forearm or either lower leg, offered on that
  limb's point, but never below a tourniquet. The AI still picks the first free site,
  left forearm first.
- Checking a body part reads only its wounds, tourniquets and line, plus the airway on the
  head and breathing and pulse on the chest (with a pulse oximeter, the SpO2 and pulse).

### Wave 3, part 4: surgery kits and the other damage

#### Added

- **Surgery kits** with 2, 3 or 5 uses (common, uncommon, rare). One use is a hemostat
  clamp (about 20 s, players and medics only). It is the only fix for internal bleeding
  from the torso arteries and veins, and it also works on junctional and arterial bleeds.
  It can close a chest wound in place of a seal, but a closed chest wound has a 10% chance
  to reopen each time the casualty sprints, jumps or sets off under an extreme load, which
  brings back the open wound and its tension risk.
- **Blast overpressure** within 5 m of a frag (10 m indoors): ears ringing for 20 to 60 s,
  a concussion check, and some bruising. Within 3 m (6 m indoors) there's a chance of
  **blast lung** (toned down on Captain's call, 2026-10-11, so it's never a death timer you
  can't answer). It takes some SpO2 and stamina, then holds steady while the casualty
  rests. Sprinting, jumping, an extreme load or IV fluid the body doesn't need make it
  worse, and the strain eases off over about 20 minutes of rest. Exertion can also
  collapse a lung, a closed tension pneumothorax that the decompression needle fixes.
  Within 2 m the blast also burns.
- **Falls:** nothing under 3 m. From 3 to 6 m, leg pain and a 30 to 70% chance of a broken
  leg. Above 6 m the fall is more and more likely to be fatal (90% from 10 m).
- **Burns:** pain by the share of the body burned. Over 20% they also lose fluid like
  bleeding, which IV fluids replace. **Burn dressings** (5 s) take some pain off, one per
  10% of the body burned.
- **Hypothermia:** 30% or more blood lost and lying still for 5 minutes makes bleeding 25%
  faster. A **hypothermia blanket** (5 s) stops it, and medics put one on after the bags.
- **Deafness:** blasts, flashbangs (3 to 6 s) and sustained gunfire indoors (30 s, after
  about ten shots close by) muffle hearing through a low-pass on the sound bus, with an
  "Ears ringing" note. **Electronic ear protection** (carried) stops flashbang and gunfire
  deafness and halves a blast's.
- Checking someone shows "Coughing blood" (blast lung), "Shivering, skin cold", "Burns over
  about N% of the body" and, on yourself, "Ears ringing". Clamped and surgically closed
  wounds say so.
- The medic's kit adds a 3-use surgery kit, two burn dressings and a blanket. The gate loot
  has a 2-use and a 5-use surgery kit, burn dressings, blankets and ear protection.

#### Fixed

- The interaction test waited 3 process frames for the host's carry update, which runs in
  the physics step, so it sometimes failed on a fast machine. It now waits physics frames.

### Wave 3, part 3: heart rate, drugs, CPR and the defibrillator

#### Added

- **Heart rate** (hidden, like SpO2). It sits at 75 bpm at rest. Blood loss and pain speed
  it up, and morphine and very low SpO2 slow it. It sinks toward 40 bpm as blood loss nears
  50%, and it's 0 in cardiac arrest. Racing over 200 bpm or slower than 35 bpm for a minute
  stops the heart. Checking someone shows "Pulse racing", "Pulse fast and weak", "Pulse slow"
  or "No pulse", and a pulse oximeter now also shows the pulse.
- **Epinephrine** (medic, 2 s): +30 bpm per dose, wearing off over a few minutes. In
  cardiac arrest it raises the chance that CPR and shocks restart the heart. It keeps its
  wake-up roll: given to someone kept out only by a concussion knockout (or already coming
  round), there's a 50% chance they come round in 2 s. It can't wake anyone while blood
  loss, low SpO2, pain, trauma or arrest still holds them. There's no revive.
- **Atropine** (2 s): raises a slow heart rate, for example after a morphine overdose.
  **Adenosine** (2 s): slows a racing one, for example after too much epinephrine.
- **CPR** (a 10 s cycle, no item needed) and the **defibrillator** (a 5 s shock; not used
  up) restart a heart in cardiac arrest only once blood is back above 60%. Until then
  they do nothing, so the line and bags come first. Each CPR cycle restarts it 8% of the
  time and each shock 35%, plus 15% with epinephrine in the blood. Among the AI only
  medics do CPR and shocks; players can always do them.
- Treat menus and AI medics follow the order: line and bags, epinephrine, shocks, CPR, then
  adenosine or atropine for a heart rate out of range. A medic keeps doing CPR and shocks
  for as long as the 10-minute window lasts.
- The medic's kit adds three epinephrine, two atropine, two adenosine and a defibrillator.
  The gate loot has two epinephrine, one of each of the other two drugs and a defibrillator.

### Wave 3, part 2: breathing, the decompression needle and the pulse oximeter

#### Added

- **Per-lung breathing.** Each lung has an efficiency from 0 to 1, lowered by collapse
  (pneumothorax) and by blood in it (hemothorax). SpO2 now follows the two lungs, blood
  loss and morphine, instead of fixed amounts per chest wound.
  - An unsealed chest wound lets its lung collapse 40% over about 12 s. Once it's sealed
    the lung re-expands over 2 minutes.
  - While a chest wound bleeds, the blood fills that side's lung, and it stays there:
    there's no chest drain in the field, so seal chest wounds early.
  - A tension pneumothorax collapses its lung fully and squeezes the other one (40% off).
- **Decompression needle** (medic, 5 s): relieves a tension pneumothorax at once, so the
  cardiac arrest it was heading for doesn't happen. Treat menus and AI medics use it right
  after the airway, before chest seals.
- **Breathing rate** (hidden): faster as the lungs fail or blood is lost, slower on too
  much morphine. Checking someone now shows "Breathing fast" or "Breathing slow", "No breath
  sounds on the left/right" for a collapsed lung, and "Trachea shifted, neck veins bulging"
  for a tension pneumothorax.
- **Pulse oximeter:** carry one and Check condition (and Check wounds on yourself) reads
  the SpO2, or "no reading" in cardiac arrest.
- The medic's kit adds two needles, a pulse oximeter and a second IO kit. The gate loot has
  two needles and an oximeter.
- AI medics keep trying for a line up to 4 times (a missed IV uses a catheter) before
  leaving it to someone else.

### Wave 3, part 1: IV and IO lines, fluids, pressure bags

#### Added

- **IV catheters** in 10, 12, 14, 16, 18 and 20 gauge. Bigger bores run fluid in faster
  (5x down to 0.6x the 18 gauge), take longer to place (22 s down to 8 s), hurt more and are
  rarer. An IV goes in the left forearm (the right if the left arm has a tourniquet).
- **IO kit:** a sternal line in 5 s that always works, at the 18 gauge rate.
- **Saline and blood bags** of 250, 500 and 1000 mL. They work the same; one bag runs at a
  time and takes about 2.75, 4.5 or 7.5 minutes through an 18 gauge.
- **Pressure bag:** doubles the flow of an IV with good veins or an IO. From 37% blood lost
  the veins collapse: an IV then runs at half its rate, or 1.25x under a pressure bag.
- **IVs in shock:** from 25% lost an IV takes longer to place (up to twice as long) and can
  miss (up to 60% of the time at 50% lost), which uses up the catheter. In deep shock and
  cardiac arrest, IO is the better pick.
- Treat menus list a line from 15% blood lost, then a bag, then a pressure bag once veins
  collapse, with one entry for each kind you carry. You can't put a line in yourself, but
  you can hang a bag on your own line. Checking someone shows their line and bag.
- AI medics put a line in (IO first when veins have collapsed), hang a bag and add a
  pressure bag after bleeding control and before splints. A squadmate without the items
  calls the medic for them.
- The medic's kit adds three 18 gauge and one 14 gauge IVs, an IO kit, two 500 mL saline
  bags, a 500 mL blood bag and a pressure bag. The gate loot has IVs (one rare 10 gauge),
  an IO kit, saline, a 1000 mL blood bag and a pressure bag.

#### Removed

- **Slow blood recovery** (the stand-in until IV): blood no longer comes back on its own.
  A casualty past 40% lost stays out until fluids bring them back under it.

### Captain's wave 2 playtest asks

#### Added

- **Inventory screen, Star Citizen style:** Tab opens a full-screen personal inventory. A
  live 3D preview of your soldier and his kit sits in the middle (drag him to turn him), with
  the equipment slots (helmet, carrier, backpack, plates, primary, sidearm) down both sides.
  Containers are on the left as grids of item tiles (carrier pouches, vest, pockets,
  backpack, hands, and what's on the ground within reach); the selected item's details and
  actions are on the right. Every tile shows a preview image rendered at runtime from the
  item's own voxel model (cached per item; a coloured tile where nothing renders) with its
  name and a mass, count or condition readout.
  - Drag tiles between containers, pouches and slots; onto the soldier to equip or attach;
    onto the ground panel to drop; from the ground panel to pick up. Right-click a tile for
    its actions (equip, attach, stow, use, load magazines, move, drop), double-click for the
    first. Load magazines also has a button at the top of the containers when you have
    loose rounds to load. Everything still goes through the host's requests.
- **MOLLE attachments:** carriers have typed attach points (light 6, medium 9, heavy 12:
  mag, pistol mag, knife, radio, medical and utility). New attachables: single and double
  M4 mag pouches, double pistol mag pouch, radio pouch (and an AN/PRC-152 radio), binocular
  pouch (and binoculars), GP utility pouch, sustainment pouch, IFAK pouch, grenade pouch and
  a fixed-blade knife, all with mass. Pouches hold their contents (a double mag pouch two
  rifle magazines, an IFAK pouch medical items, a sustainment pouch anything small).
  - The MOLLE view (click the carrier twice, or the MOLLE button) closes in on the carrier
    and lays its attach points down the sides with lines to where they sit; drag compatible
    items onto them, or drag an attached pouch to another point.
  - Attachments stay on the carrier: dropping, picking up, looting or stowing a vest keeps
    its pouches and what's in them, and they're saved with the zone and replicate.
  - Reloads take magazines from mag pouches first; magazines, grenades and medical items you
    pick up go into the pouches made for them first. Pouches and their contents count in
    your mass. Attached pouches show on the soldier as small boxes on the carrier.
  - Role kits put three double mag pouches and an IFAK pouch on every carrier; the team
    leader adds a radio and binoculars, the medic a sustainment pouch and a knife, the
    grenadier grenade pouches, the marksman a pistol mag pouch and binoculars, the
    autorifleman and rifleman a GP pouch (and the rifleman a knife). Pouches lie in the
    compound loot west of the gate.
- Tests: MOLLE rules (points, pouch capacity, reload from pouches, detach and re-attach,
  mass, save round trip) and MOLLE through the host and the inventory screen (attach,
  move, detach, drag and drop, drop and pick up a carrier with pouches) in the logistics
  suite.

#### Changed

- Moving a stack into a container that can't take all of it moves as many as fit.
- Dropped items saved with the zone come back with whole numbers and item ids restored
  (like bodies already did).

### Captain's wave 2 playtest fixes

From Captain's playtest of the wave 1 build. The Star Citizen-style inventory and MOLLE vest
attachments Captain asked for at the same time are under "Captain's wave 2 playtest asks" above.

#### Changed

- **Plate and helmet wear:** every hit, stopped or not, now wears a plate or helmet down by
  round class and the piece's durability, and the HUD shows that integrity (it used to show
  only the share of voxels knocked out, so a heavily dented plate still read 94%). A 5.56 round
  takes about a quarter of a light PE plate (worn out in 4 hits), 18% of a heavy ceramic plate
  (6) and 8% of a medium steel plate (13). Helmets: bump 30%, medium 23%, heavy 18% per hit.
  Below 30% a steel, PE or composite piece starts letting rounds through, and at zero it stops
  nothing ("worn out"; ceramic still shatters).
- **Plate-stop pain:** a burst into the plates hurts. Each stop adds more impact (pistol 0.05,
  5.56 0.12, 7.62 0.22), up to 0.7, which was 0.35. Six 5.56 stops in a row reach the cap.
  That plus a cracked rib stays just under the knockout threshold at full blood, so plates
  alone still never knock out a healthy soldier, but a wounded one who has lost blood can go
  down.
- **Bullet holes in wood and sheet metal** are now the size of the round: a dark core the
  bullet's diameter (5.7 mm for 5.56, 7.8 mm for 7.62, 9 mm for 9 mm) in a splintered or
  bare-metal rim, going in and coming out (bigger on the way out of wood), instead of a whole
  10 cm voxel knocked out. A voxel breaks out only after 10 rounds through it (16 for sheet
  metal). Every peer sees them, late joiners too, and they're saved with the zone. Old saves'
  whole-voxel holes still load.
- **Knees:** legs bend at the knee. Crouching and kneeling put the feet under the hips, with
  the back knee down on the ground, and knees fold as the legs swing through when walking.
  Shin hitboxes follow the shins.
- **Dragging, Arma-style:** you face the casualty and crouch over them, and the view goes
  down with you. You back away with S (strafing works, W doesn't walk onto them), and the
  camera turns round with you when you take hold or let go. Looking at the body you drag (or
  carry) offers **Release** (or Put down) in the Ctrl menu, as well as in the Ctrl+Alt menu.

#### Fixed

- Looking far up or down could tip the view past vertical, swing it round about 90 degrees
  and leave you facing backwards, with mouse look or movement inverted. The cause was leaning
  (and the stance tilt) leaking into the view's turn on every mouse move. The view now stops
  at about 83 degrees up or down and can't turn away from the body.
- AI squadmates keep the older, looser momentum. The player's tighter grip from the movement
  fix left them stuck on door frames.

### Captain's wave 1 playtest fixes

All five fixes, each built, reviewed and fixed by its own agent. The movement fix (sliding
as if on ice) came last, on `fix2/p2-movement`.

#### Changed

- **Movement feel:** no more sliding on ice. Stopping now takes about 0.2 s from a jog or a
  sprint (0.4 m from a jog, under 0.9 m from a sprint; was 0.6 m and about 1.6 m), and
  after a turn, or when the view swings round mid-run, the old heading is shed in 0.1 s
  (about 0.2 m of drift on a 90 degree turn) while the new direction builds up over the
  usual 0.3 s. Gentle turns keep their pace. A full load still doubles all of it.

- **Knockouts:** getting hit in the plates no longer knocks you out. Stopped rounds bruise
  (plate impact pain about halved and capped at 0.35 however many land), still stagger you,
  and 7.62 still winds you. A medium-armor soldier hit 2-3 times, or 6 times in a burst,
  stays conscious and fighting.
  - Pain knocks you out only when it stays at the threshold for 3 seconds, not on a brief
    spike. One rifle round through a limb hurts (pain 0.45-0.65, was 0.6-0.9) and often
    breaks the bone, but doesn't knock a healthy soldier out. Pistol wounds 0.25-0.4.
  - Steel spall is rare and minor: 5% of pistol, 10% of 5.56/7.62x39 and 20% of full-power
    stops, one wound at most, usually a scratch. It used to be 1-2 wounds on every stop.
  - Cracked ribs from plate stops are rarer and depend on range (5.56: 20% point blank,
    none past 100 m).
  - Two .308 helmet stops no longer knock you out on their own; it takes three, or the
    concussion roll.
- **Armor voxels:** plates and helmets are one voxel thicker (PE and ceramic plates 3 cm,
  steel and side plates 2 cm, helmets 2-3 cm). A stopped round leaves a small dent of a few
  voxels and never a hole; only a round that gets through makes one. Repeated hits on one
  spot wear through: about 5 for steel, 3 for polyethylene and helmets.
- **World materials:** wood and thin sheet metal can be shot through, hitting whoever is
  behind with less energy (a thick stack of wood stops it). Concrete stops every small-arms
  round with no hole and takes a small 5 cm crack mark instead, seen by every player, for
  late joiners too, and saved with the zone. Frags chip concrete and blow holes in planks
  and sheet metal. The compound now has concrete, sandbags, wooden crates, a wooden shed
  with a sheet-metal roof and a shipping container. AI prefers concrete and sandbag cover.
- **Animations:** fireman's carry (the casualty limp over your shoulders), drag (backing
  away in a crouch holding the carrier straps, casualty on their back head first), pick up,
  equip, stow and drop (hand to the slot), weapon draw, treating (kneeling, hands at the
  wound) and looting. Every player sees them, including late joiners, and hit areas follow
  the poses. In first person the view model drops out of the way. You can't fire while
  dragging.

#### Fixed

- Plates, helmets and armor lying on the ground take damage: they dent, crack and lose
  integrity like worn armor, and keep it when picked up.
- Plates (especially thin steel ones) that landed face first could sink into the ground or
  crates and couldn't be picked up.
- The smoke suite's random "plate protected the body" failure.
- Tests: new materials and animations suites (14 suites by default).

### Wave 2 of the build plan (phase 3 finish)

Built by three agents in parallel (kit and treatment, AI casualty care, ammo and smokes),
then finished by two more after Captain's direction mid-wave: no revive, bodies keep their
gear, medics put the wounded first. Merged on `dev`. See `docs/build_plan.md`.

#### Added

- **Field kit on the wound model:**
  - The IFAK and trauma kit are bags of real items. IFAK: 1 tourniquet, 2 pressure
    bandages, 1 hemostatic gauze, 1 vented chest seal. Trauma kit: 2 tourniquets, 4
    bandages, 2 gauze, 2 seals, 1 splint, 2 morphine, 1 NPA. Loose items are used first,
    and the inventory screen shows what's left in each kit.
  - Treat yourself (Left Ctrl + Left Alt) or others (Left Ctrl): a Treat submenu lists
    what's needed in casualty-care order with the body part ("Tourniquet, left thigh"),
    greyed out with a reason when you don't carry the item. H applies the next item for
    your own most urgent wound.
  - Times: tourniquet 4 s (6 s on yourself), bandage 5 s, gauze 8 s, chest seal 5 s, splint
    8 s, morphine 2 s, NPA 3 s. Moving away, going down, or the casualty being moved
    interrupts it without using the item.
  - Tourniquet: stops all bleeding on that limb below it and adds pain; on a leg you limp.
    A rushed one (1.5 s, or any put on under fire) only stops 70%; a second beside it fixes
    that. Packing the wound with gauze lets you take it off again.
  - Bandages fix venous, muscle and graze wounds; gauze packs junctional bleeds. A vented
    chest seal stops tension pneumothorax from starting (it can't relieve one already
    started). A splint lets you jog on a broken leg and steadies a broken arm.
  - An unconscious casualty's airway can block; an NPA prevents or clears it. A short
    spell out (under 45 s) clears its own airway.
- **Consciousness follows the body (no dice):** you stay out while any cause holds: low
  blood oxygen (SpO2 under 85), pain at the knockout threshold, 40% of your blood lost,
  cardiac arrest, a concussion, morphine sedation, or too many serious wounds at once
  (total trauma). About 10 to 20 s after the last cause clears you come round on your own.
  - **SpO2** (hidden): falls with heavy blood loss, an unsealed chest wound, tension
    pneumothorax, a blocked airway and too much morphine. Your vision greys and closes in;
    a medic checking you sees laboured breathing and blue lips. About 2 minutes under 70%
    stops the heart.
  - **Morphine** is a level in the blood: a dose goes in over 30 s and halves every 12
    minutes, and pain relief follows the level. Two doses are fine, three sedate, five or
    more slow breathing dangerously.
  - **Slow blood recovery** (Captain's stand-in until IV in wave 3): once every bleed has
    stopped, internal ones too, the body makes back 1.5% of its blood a minute, so a
    patched-up casualty past 40% lost comes round after a few minutes. Any bleeding stops it.
  - Check condition shows plain signs: Unresponsive, Breathing laboured, Blue lips,
    Pinpoint pupils (morphine).
- **AI casualty care:** the fire team's medic answers first, then the battle buddy, then
  the other medic ("Moving to Charlie", "Treating Charlie"). Medics put the wounded first
  even in a firefight: smoke between a casualty in the open and the threat, drag to cover,
  massive bleeding first, the rest once in cover; they fight back only at close range, and
  the rest of the squad covers them. Afterwards they stay with an unconscious casualty or
  carry them with the squad until they wake. A wounded squadmate puts its own tourniquet on
  at once and calls "Medic!" for what it can't fix. A responder that can't reach a casualty
  sidesteps and then hands them to someone else.
- **Bodies keep their gear:** every dead player, squadmate and enemy leaves a body where they
  fell with everything still on it; only something carried in both hands drops. Left Ctrl on
  a body: Loot (take one thing), Loot all (what fits; the rest stays on the body), Carry,
  Drag. Bodies and their gear are saved with the zone and appear for late joiners. Past 12
  bodies the oldest goes and its gear drops where it lay.
- **Ammo:** loose 5.56, 7.62x51 and 9mm rounds; magazines weigh what they hold; empties go
  back in the pouch and stack. "Load magazines" on loose rounds (inventory screen) fills that
  calibre's magazines, fullest first, at 5 rounds a second; moving or firing stops it.
- **Coloured smoke:** green, yellow, blue and purple grenades (for the wave 5 supports);
  Shift+G cycles through what you carry. Coloured smoke blocks AI sight like white.
- Tests: medical, casualty (including a two-lap soak and an under-fire engagement) and
  logistics suites, in the default run (12 suites).

#### Changed

- You respawn with an M4, 2 spare magazines and 90 loose rounds, a smoke and a frag. Your
  body stays where you fell with your old gear, and the gear marker floats over it.
- Medics carry a trauma kit and extra tourniquets, gauze, bandages, seals, splints, morphine
  and NPAs; everyone else carries an IFAK.
- A dead squadmate leaves the squad (no slot, no orders, not on the roster) and isn't
  replaced this session.
- Squad AI routes through breached walls: once a gap is big enough to fit through, the
  navigation around it updates within a fraction of a second.
- Enemies and squadmates leave unconscious foes alone, except a dead-check within about 8 m
  while assaulting or searching a position.
- Squadmates pass through each other (no more doorway jams); AI only throws a frag when its
  arc is clear.
- The zone save keeps full number precision, so armor damage comes back exactly.

#### Removed

- **The stopgap revive.** There's no Revive anywhere: casualties come round when their body
  lets them. The 15% wake roll and the morphine overdose dice are gone too.

#### Fixed

- Dead players, squadmates and enemies no longer vanish or scatter their gear on the ground.
  Players joining or changing roles no longer delete dead squadmates' bodies.
- AI medics no longer get stuck behind a player standing on their route.

### Wave 1 of the build plan (phase 3 core)

Built by five agents in parallel and merged on `dev`. See `docs/build_plan.md`.

#### Added

- **Wound model (no more hitpoints):**
  - Hits make wounds on 14 body parts. Arteries and big veins bleed by how close the round
    passed, so a femoral hit takes about 2 to 3 minutes to knock you out.
  - Bones can break: a broken leg means no sprint and walking speed; a broken arm means
    heavy sway and slow reloads.
  - Heart hits stop the heart within seconds, lung hits open the chest (with a chance of
    tension pneumothorax), and a head hit past the helmet is fatal.
  - 6 L of blood. From 15% lost you sway more, recover stamina more slowly and move slower;
    from 30% you can't sprint; at 40% you're unconscious. At 50% the heart stops and a
    10-minute cardiac-arrest window starts.
  - Pain from 0 to 1 can knock you out, more easily the more blood you've lost. Once
    stable you have a chance to wake every 15 s.
  - Blood loss fades and greys your vision, with tunnel vision from 30% lost. Unconscious
    shows a black screen with UNCONSCIOUS or a cardiac-arrest countdown.
  - Frag grenades cause 3 to 8 fragment wounds on exposed parts; walls, other bodies,
    plates, helmets and vests stop them.
  - Target dummy labels show condition, blood %, bleed rate, pain and wound types.
- **Armor ratings:**
  - Rounds and armor share an NIJ-named ladder (IIA to IV): armor stops what it's rated
    for and nothing above it. Light and medium helmets no longer stop rifle rounds; the
    heavy helmet stops rifle rounds up to M855 and 7.62x51 ball.
  - Plates: PE III (light), steel III++ (medium), ceramic IV (heavy); names show the
    rating. Plates only fit the right carrier (PE in the light carrier; steel and ceramic
    in medium and heavy; side plates in heavy), with a message when they don't.
  - Ceramic cracks around each hit; hits near earlier cracks get through more often, and
    enough hits shatter the plate. Cracks stay with the plate and show when inspected.
  - Steel doesn't crack but throws spall at the neck, face and arms; the medium carrier
    covers the neck, the heavy one neck, face and arms.
  - Vests are aramid soft armor that stop pistol rounds and fragments where they cover you,
    even after the plate fails.
  - Stopped rounds still hit: pain, stagger, getting winded, cracked ribs at close range,
    concussions from helmet hits, and rarely a fatal helmet stop from a full-power rifle
    within about 200 m.
  - ACE3-style ballistics: rounds lose energy with range (M855 from far enough away is
    stopped by a light plate).
- **Stances and handling:**
  - X crouch and Z prone (toggles); Caps Lock + W/S steps through three standing and
    three crouching heights and prone; Caps Lock + A/D for side stances.
  - Q/E lean: hold, double-tap to stay, tap to return; leaning stops short of walls.
  - C rests the weapon on a surface for half the sway and recoil until you move.
  - F fire mode: M4 and Mk18 have semi and auto and start on semi.
  - Movement has weight: about 0.3 s to reach a jog or stop, roughly double under a heavy
    load, with momentum into turns and a moment of sway after a hard stop.
  - Sprinting uses stamina (about 15 s from full, less under load). No sprint or jump
    while crouched or prone. Prone is steadiest, then crouched.
  - Hitboxes follow the pose, so crouched and prone soldiers are lower targets.
- **Interaction menus (ACE-style):** hold Left Ctrl for action points on items, downed
  bodies and squadmates within about 3 m; hold Left Ctrl + Left Alt for yourself. Actions:
  pick up, revive, carry (55% speed), drag (35%, the body slides behind you), check
  condition, check your wounds, use medical, put down, drop held item, and give a stowed
  item to a squadmate.
- **Squad roles and fire teams:**
  - Two fire teams of four (A and B), each with a medic. Roles: team leader, medic,
    autorifleman, grenadier, marksman, rifleman, with starting kits for AI squadmates.
  - Pick your role on the main menu; AI fills the rest.
  - Command menu: Target (focus fire), Combat mode (Safe, Aware, Combat, Stealth) and Team
    (fire teams and colour teams). F1-F8 follow squad slots; Shift+F-key adds.
  - Squadmates call out subtitles: contacts with direction and distance, reloading, man
    down, frag out, smoke out, moving and covering. Voice lines play once audio exists in
    `audio/callouts/`.
  - The HUD roster shows fire team, role and colour team.
- **Tests:** new suites `wounds`, `armor`, `movement`, `interaction` and `roles`;
  `tools/run_tests.sh` runs all nine by default.

#### Changed

- E leans right; picking up and reviving moved to the Left Ctrl menu. Ctrl and C no longer
  crouch.
- IFAK and trauma kit are stopgaps until the wave 2 kit: using one stops bleeding wound by
  wound and takes off pain; reviving stops all bleeding, brings blood up to 62% and
  restarts the heart.
- The debug K key costs 24% of your blood and adds pain; two presses knock you out.
- Squadmates no longer fire through you or each other, battle buddies don't move to new
  cover at the same time, and AI aims at your chest wherever your stance puts it.
- Downed bodies get a lying-down movement capsule (they used to block as an invisible
  upright body).

#### Fixed

- `tools/run_tests.sh` exits non-zero when a suite fails.

Phase 2, inventory depth: ammo, reloading, healing, an inventory screen, and item state
that travels with the item.

### Added

- **18 new voxel materials** for the worldspaces, with fixed colours from the faction pack's material registry: mud brick, stone, limestone, basalt, tuff, coral stone, brick, cinder block, plaster, roof tile, fibre cement, corrugated iron, thatch, tarp, glass, sandbag, HESCO and dirt berm. They are colours only for now; all materials still carve the same way.
- **Squad AI (phase 3, first pass):** the player squad has 8 slots, and AI fills every slot players don't (7 squadmates for one player, 4 for four). See `docs/squad_design.md`.
  - Arma 3-style command menu: F1-F8 select squadmates by number (~ for all), then 1-9 / 0 or the mouse wheel and middle click pick orders: move (formation, move there, stop), engage (open / hold fire), status, action (throw smoke or frag at the crosshair), formation (wedge, file, line, staggered column) and a support menu (not built yet). Orders go to the selected units; the last player to give one leads.
  - Everyone is paired into battle buddies. In a fight, soldiers take cover, crouch when not shooting, get pinned by close fire, and buddies take turns moving while the other covers. Frags go to enemies hiding behind cover.
  - Downed friendlies (players too) get help, buddy first: in a fight, smoke and a drag to cover, then a revive or a guard; out of a fight, a revive, or the buddy carries them and follows the lead.
  - Hostile fire teams (two guards, two on patrol) use the same body and AI.
  - A runtime navmesh over the compound. The HUD lists each squadmate's status and health.
  - `tests/squad_test.tscn`: roster scaling, navigation, following, a buddy carrying a buddy, a firefight and flashbang stun.
- **Grenades (G to throw, Shift+G to switch type):** frag, flashbang (new item) and smoke.
  - Frag: up to 180 damage within 8 m, falling off with distance; walls shield you. It also blasts a crater in voxel walls.
  - Flashbang: whites out the screen for up to 5 s, depending on distance and whether you were looking at it. AI soldiers will be stunned.
  - Smoke: a 5 m cloud that lasts 30 s. It blocks the view, and will block AI line of sight.
  - Every peer sees the grenade fly; the host detonates it. The compound has smokes and flashbangs next to the frags.

- **Item state:** items carry state that goes wherever they go: rounds in a weapon or
  magazine, chips in a plate or helmet. It's kept while the item is worn, stowed, dropped,
  picked up by someone else, and saved with the zone.
- **Ammo:** weapons come loaded and every shot uses a round. Firing an empty weapon tells
  you to reload.
- **Reloading (R):** loads the fullest compatible magazine you carry. A part-used magazine
  goes back where the new one came from, and an empty one is discarded. Reload times are
  per weapon (pistol 1.6 s, M110 2.8 s); you can't fire while reloading. Other players see
  your left hand working the magazine.
- **Medical items (H):** IFAK (+35 HP over 4 s) and trauma kit (+70 HP over 8 s). You get
  the smallest kit that covers your injuries; using one keeps your hands busy for a moment.
- **Inventory screen (Tab):** equipped slots and container contents, with Equip, Stow,
  Use, move to another container, and Drop. Rounds loaded, part-used magazines and armor
  damage are shown on each item.
- **HUD:** ammo counter (loaded / spare rounds) and reloading and healing indicators.
- **Aiming down sights (hold RMB):** zooms to each weapon's aim FOV (M110 30°, pistol 65°),
  lines the weapon's sight up under your eye, and cuts spread to 12% of hip fire. It also
  halves recoil and slows movement.
- **Spread and recoil:**
  - Each weapon has a spread cone, which widens while moving (up to 2.5×) or in the air (2.5×) and tightens when crouched.
  - Each shot kicks the view up and slightly sideways.
  - Stats per weapon: `spread_deg`, `recoil_deg`, `ads_fov`.
- **Downed and revive:**
  - At 0 HP you go down instead of dying: you fall face down, can only crawl, can't shoot, and drop anything you're carrying in both hands.
  - You bleed out after 60 s. Another hit while down kills you. There is no giving up.
  - Teammates revive you with E: a trauma kit takes 3 s and brings you back at 50 HP; an IFAK takes 5 s and brings you back at 25 HP. The kit is used up when the revive completes.
  - Hitboxes lie down with the body, so shots land where you're lying.
  - Dead bodies lie down too. Target dummies get back up on their own after a few seconds.
- **Ground items:** the pickup prompt shows rounds and damage. Armor on the ground shows its chips.
- **Docs:** `docs/squad_design.md`, the phase 3 squad AI design (body/driver split,
  navigation, utility intents, co-op command, inventory loop, permadeath), with the decisions made.
- **Test builds:** `tools/make_build.sh <label>` leaves a playable build in
  `builds/<date>_<label>/`: a small `contractor.pck`, a `play.bat` launcher that runs it with
  the Voxel Tools Godot (no export templates needed) and a `BUILD.txt`. Builds stay local
  (`builds/` is git-ignored).
- **Debug key K** (debug builds only, which includes test builds): hurts you by 40 so going down and dying can be tested solo.
- `Inventory.strip()` empties a body's whole inventory into entries that keep their state.
- **Tests:**
  - `tests/gameplay_test.tscn`: end-to-end checks of a hosted session through the real requests a client sends.
  - `tests/net_test.tscn`: a two-process ENet host and client.
  - `tools/run_tests.sh` runs every suite.
  - The smoke test now has 88 checks. The gameplay test covers spread, aiming, going down and reviving, and a host-owned AI body driven through the same API, and the new death rules.

### Changed

- **Design authority:** `docs/contractor_handoff.md` (Captain's decisions, 2026-10-10) now
  overrides the README's locked decisions and `docs/squad_design.md`. Both were updated to
  match: 8-slot squad, wound model, minimal HUD, new death rules, new controls.
- **Player death:** you respawn in the default kit (M4, 2 spare magazines, a smoke and a
  frag). Everything you carried stays where you died, under a floating marker that clears
  once the gear is picked up. Before, you respawned with all your gear.
- **AI death is permanent:** an AI soldier that dies doesn't respawn; its gear stays where it fell.
- **Soldier split (build plan wave 0):** `scripts/actors/soldier.gd` is now three parts so
  parallel work doesn't collide: `soldier_movement.gd` (Movement node), `player_input.gd`
  (PlayerInput node: the human driver, camera, view model, HUD) and the body with its
  host-side requests. No behaviour change.
- **Wound-model interface:** everything outside `Vitals` now goes through named calls
  (`server_hit(part, hit)`, `server_impact`, `injury()`, `condition_text()`,
  `seconds_to_death()`, `speed_mult()`, `sway_mult()` and others), backed by HP until the
  wound model replaces it. Hitboxes name their body part in a `body_part` meta (was
  `damage_mult`); `Vitals.net_state` is replicated for the wound model's extra state.
  Squad reports and dummy labels show a condition instead of HP.
- **Planned keys** (README, "Decided, not built yet"): stance adjust moves to holding Caps
  Lock + WASD, interaction to holding Left Ctrl and self-interaction to holding Left Ctrl +
  Left Alt, instead of the handoff's Ctrl+WASD, Left Windows and Ctrl+Left Windows.
- **No giving up:** a downed player can only wait for a revive or bleed out. F no longer
  does anything while down (it's reserved for fire mode); `Vitals.server_give_up` is gone.
- **Minimal HUD:** no health, ammo, grenade count, load or armor readout, as in Arma with
  ACE. The squad roster shows what each squadmate is doing, without health. Weight,
  litres, rounds loaded and armor damage are on the inventory screen (Tab).
- Keys: G throws grenades (Shift+G switches type) and Alt+G drops; F-keys are the squad command menu, so saving the zone moved from F5 to Home.
- `Player` is now `Soldier` (`scenes/soldier.tscn`, `scripts/actors/soldier.gd`), the body both players and AI use. AI bodies have non-numeric names and are driven by the host.

- Armor damage is now the item's own state, not the wearer's. A dropped plate or helmet
  keeps its holes. `Vitals` now only tracks health and healing.
- `Inventory.unequip()` returns the item with its state. `take()` accepts state.
- `Vitals` gained the downed state (`downed`, `bleed_seconds`, `server_revive`), replicated to all peers.
- **Menu:**
  - The host button is now "Play (host a session)", with a note that solo play means hosting.
  - A failed join says that someone must be hosting at that address.
  - Join retries 3 times, about 2.5 s each, so a second window started with the host still connects.
  - Hosting on a busy port suggests joining instead.

### Fixed

- Armor lying on the ground no longer tries to set an empty node name.

## [0.1.0] - 2026-10-09

First playable gray-box foundation: a co-op player can loot, gear up and shoot through
voxel armor and walls in a test compound.

### Added

- **Engine setup:** Godot 4.7.2 with Voxel Tools 1.7 (custom editor build), GDScript, Jolt physics.
- **Co-op:** ENet listen server with up to 4 players. The host is authoritative over health,
  armor and inventory, and replicates them to everyone, including late joiners. Owners
  simulate their own movement. `--host` and `--join <address>` command-line shortcuts.
- **Player:** first-person controller with walk, sprint, crouch and jump. Carried weight
  slows you down, and bulky items slow you further and block sprinting and firing.
- **Inventory:**
  - Body slots for primary, sidearm, helmet, vest, backpack and four plate pockets.
  - Volume measured in litres: pockets 2 L, plus whatever the vest and backpack add.
  - Equipping and stowing happen automatically on pickup; bulky items (HVT case, supply crate) are carried in both hands.
  - Drop (G), weapon switching (1 and 2), and an inventory detail view (Tab).
- **Items:** 28 items in `data/items.json`: rifles, a DMR and a pistol; magazines; light,
  medium and heavy carriers, helmets and plates; side plates; backpacks; medical items,
  grenades, a breaching charge, salvage and objective items.
- **Placeholder data:** 3 factions with reputation tiers (`data/factions.json`) and 5
  mission objectives (`data/missions.json`).
- **Voxel structures:** destructible 10 cm voxel walls, cover and crates. Bullets carve
  holes. Damage is kept as an edit log that the host sends to joining players and saves.
- **Zone persistence:** looted items, dropped items and voxel damage are saved to `user://saves/`. Save with F5, on quit, or reset from the menu.
- **Characters:**
  - Procedural voxel soldiers built from 2 cm voxels, in four camo variants (multicam, woodland, desert, urban), plus crash-test-yellow target dummies.
  - Code-driven animation: walk and sprint cycles, breathing, and the head following where the player looks.
  - Elbows with two-bone IK put the palms on each weapon's grip points.
  - Rifles move between the sling and the hands, and the pistol between the holster and the hands.
- **Gear art:** voxel models for the plate carriers (light, medium and heavy), backpacks
  whose depth follows capacity, the three rifles and the pistol. They're worn on the body,
  shown in first person and lying on the ground.
- **Destructible voxel armor:**
  - Plates and helmets are made of 1 cm voxels.
  - Each round is traced voxel by voxel. If it meets material it's stopped and the armor chips; if it reaches a hole it carries on to whatever is behind.
  - Damage replicates to every peer and is replayed for late joiners.
- **Armor tiers:**
  - Light: low-profile carrier with a front plate pocket, bump helmet, polyethylene plate.
  - Medium: plate carrier with front and back pockets, ballistic helmet, ceramic plate.
  - Heavy: assault carrier with front, back and side pockets, a helmet with ear covers and a visor, and a steel plate.
- **Hitboxes:** separate colliders for movement, body, head (×3 damage) and armor.
- **Test compound:** perimeter wall with a gate, a building, cover, crates, starting loot, and light, medium and heavy armored target dummies.
- **HUD:** health, weight, litres used per container, armor condition, interaction prompts and an inventory detail view.
- **Tests:** a headless smoke test with 54 checks, and a screenshot tour that regenerates `screenshots/`.
- **Docs:** README with installation steps, controls, architecture and roadmap; this changelog.

### Known issues

- No ammo use or reloading yet.
- Armor damage stays with the wearer, so a dropped plate or helmet comes back undamaged.
- No inventory screen for moving items between containers. A vest or backpack can't be dropped while it has contents.
- The head hitbox doesn't tilt with the head; the helmet does.
- The voxel world has no stream, so zones are limited to `VoxelWorld.BOUNDS`. The edit log is never compacted.
- Player inventories aren't saved; only the zone's state is.

[Unreleased]: https://github.com/cghath/Contractor/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cghath/Contractor/releases/tag/v0.1.0
