# AI tactics by echelon: what every side does

The Captain sent ten tactics reels (2026-10-22) as training material for **all AI in the game**:
friendly, allied, enemy, every faction. Their frame-by-frame breakdown is
docs/tactics/reel_notes.md (R01-R10, synthesis A-G). This doc turns each technique into a
concrete behaviour: its trigger, the roles, the positions, the timing and what done looks like.
It's organised by the Captain's echelons:

| Echelon | Size | Who runs it in the code |
|---|---|---|
| Team | 4-6 | SquadAI (each man) and SquadTactics (the squad's evaluator), per fire team |
| Squad | 8-12 | SquadTactics, Squad's orders, SquadOrders (high command's executor) |
| Platoon | 24-48 | SideCommand (combined_arms B2): its groups as a platoon's squads |
| Company | ~160-240 | SideCommand with an OperationPlan or DefencePlan per company |
| Brigade | its companies plus a command element | SideCommand's brigade layer over its company plans |

**Every side uses all of it.** The drills are the same code for the company's squad, the hero
squads, allied units and every enemy faction; what differs between sides is doctrine (how fast,
how far, how aggressive: data/doctrines.json and SquadTactics' doctrine biases) and echelon (how
big a side can fight: section 7).

Status per technique: **built** (works today), **partial** (some of it works; the gap is said),
**new** (to build). Where it says file:function the line was checked on 2026-10-22. Numbers are
Proposed: game metres for the reels' "body-lengths" (1 body-length is 1.5-2 m), tuned in play.

Learned from, not copied from, the reels: they show US Army and USMC doctrine (FM 3-21.8 battle
drills, TC 7-100.2's opposing force) drawn as animations; Contractor's AI takes the ideas and
fits them to its own squads and factions.

## Contents

1. Rules for every echelon
2. Team (4-6)
3. Squad (8-12)
4. Platoon (24-48)
5. Company (~160-240)
6. Brigade
7. Echelons by side: state forces and terror groups that grow
8. Build plan
9. Calls made

## 1. Rules for every echelon

| # | Rule | Behaviour | Status |
|---|---|---|---|
| A1 | **Never bunch** | Moving in the open, every man keeps 6-10 m (4-5 body-lengths) from the nearest friend; taking cover, no two men share one piece of cover unless they're a bound pair | partial: Squad `SPACINGS` and context spacing; SquadAI `_keeps_apart` (friendlies only, 3 m); cover gap 2.5 m. **New:** cover spots at least 6 m apart unless bound pairs, for every side; the separation rule for hostiles too |
| A2 | **Cover on contact** | The first shot: each man goes to his own nearest cover, stops, returns aimed fire | built: SquadAI `_contact_drill`, `react_to_fire`; **new:** pinned hostiles crawl to cover as friendlies do |
| A3 | **Every action has an end state** | Consolidated with all-round security, at a rally point, or at a limit of advance; then an ammo and casualty check | partial (high command's attack only). **New:** squad tactics end in consolidation (T6) |
| A4 | **Smoke before a move or a breach** | Smoke removes the enemy's line before crossing open ground under fire, breaking contact, or breaching | mostly built: `_screen_toward_threat`, `_smoke_crossing`. **New:** smoke before a breach (T9), thrown by the grenadier role where there is one |
| A5 | **Contact differs by range and ground** | Under 35 m (hand-grenade range) is a near ambush and gets the charge-through; beyond, cover and fire and flank; fortification and numbers change the drill | partial: SquadTactics' ASSAULT under 35 m at 2:1. **New:** the near-ambush drill (T1) |
| A6 | **Fire superiority first** | Movement only once the base of fire is set and firing and the leader signals; fire without movement wastes ammo, movement without fire is suicide | built for the commander (B2's sync). **New at squad level** (T4) |

## 2. Team (4-6)

The team: team leader (TL), automatic rifleman (AR), grenadier (GRN), rifleman (RFLM); a fifth
or sixth is a designated marksman or a medic. Roles (scripts/ai/roles.gd) already give men these
jobs; the drills below use them by role, else by what each man carries.

### T-B1 Patrol movement and rally points (R01, R04)
- **Trigger:** a team moving with no known contact.
- **Roles and positions:** a staggered wedge (Squad `pick_formation`, built); the rifleman on
  point, eyes up; the TL behind and central; AR and GRN on the flanks; spacing A1.
- **Rally points (new):** every 150 m of travel (100-200) the TL names a rally point: the best
  covered spot 30-60 m back along the route (a wall, a rock, a building corner) with room for the
  team to face out. "Rally point Alpha, the wall behind us." The latest one is the team's
  `rally` (Squad.tasking.rally, declared and so far unread), used by break contact (T-B4).
- **Done:** at the next cover with every man watching his arc.
- **Status:** formation built; rally points **new**.

### T-B2 Contact report: the three D's (R04)
- **Trigger:** the first man to see the enemy or take fire.
- **Says:** "Contact! Twelve o'clock, seventy-five metres, three men!" Direction (clock in shouts,
  cardinal on the net), distance, description (how many and what: a gun, an RPG).
- **Done:** every man knows bearing, range and count; the TL calls the drill.
- **Status:** partial (Callouts.contact has direction and distance; **new:** the count and what's
  seen, and hostiles' reports by shout as friendlies' are).

### T-B3 Immediate reaction: near and far ambush (R01, R05)
- **Far (first shot beyond 35 m):** drop, each to his own cover, heavy suppressive fire, smoke
  between, a base of fire; the uncommitted men flank. Built (SquadTactics SUPPRESS_FLANK with smoke
  on the manoeuvre legs).
- **Near (new, T1):**
  - **Trigger:** the team is fired on from within 35 m by an enemy line in the open or in a kill
    zone (two or more enemies, or the first burst from under 35 m), and it isn't pinned in cover.
  - **Behaviour:** no cover-seeking. Every man returns violent fire at once (the AR on full auto,
    the riflemen rapid); the men with frags throw them; 2-3 s later the free men (all but the AR and
    one rifleman, who keep firing) charge straight through the enemy line, firing.
  - **Done:** the team is through and consolidates on the far side, facing back: all-round
    security, ammo and casualty check.
  - Learned from R05: "you can't take cover in a kill zone".
- **Don't treat in the open:** while the team is under effective fire no one stops to treat a
  casualty in the open; the casualty is dragged to cover first (built: the carer cap and the drag).

### T-B4 Break contact, Battle Drill 3 (R04)
- **Trigger:** the TL judges the fight unwinnable: outnumbered (SquadTactics' ratio), a man down
  with no cover, or ordered. Built as a tactic (BREAK_CONTACT); the sequence is **new (T2)**:
  1. The grenadier (else whoever has smoke) throws smoke between the team and the enemy.
  2. The AR and one rifleman keep firing: auto plus aimed shots.
  3. The man furthest back goes first: "Moving!", bounds 10-15 m to cover, "Set!".
  4. On "Set!" the next furthest back goes, and so on, each covered by whoever is set.
  5. All at the rally point (T-B1's, else 60 m straight back from the enemy): a perimeter facing
     the enemy, then ammo and casualty check; hold or push back.
- **Timing:** 3-5 s exposed per bound.
- **Done:** every man "Set" at the rally point, facing out.

### T-B5 Bounding: up, he sees me, down (R03)
- One of a pair always firing while the other moves cover to cover; 3-5 s up. Built (SquadAI
  `_bound_toward`, legs of 10 m, the buddy holding while the other bounds). **New:** the covering man
  fires at the threat while his buddy moves (today he crouches and watches).

### T-B6 Support by fire (R02, R03)
- **Position:** cover with a field of fire on the enemy; the men in a line abreast 5-8 m apart,
  prone or kneeling.
- **Sectors (new, T5):** each man a wedge of 30-40°; adjacent wedges overlap; together they cover
  the whole enemy position and both its flanks (so it can neither reinforce nor withdraw). Never all
  on one man: the shooters spread over the known enemies and the ground beside them.
- **Weapons:** the AR and the grenadier give sustained fire and grenades.
- **Relocating (new):** after 3-5 bursts from one spot, a man shifts 2-4 m left or right or lower
  (a marksman waiting on the same spot is how SBF gunners die).
- **Shift and lift (new at squad level):** as the squad's assault closes within 50 m of the
  objective, the base shifts its fire to the far side of the objective; with the assault within 25
  m or on it, it lifts and watches the flanks. Built in high command (SquadOrders `_tick_sbf`).
- **Done:** SBF silent, every eye on the flanks and rear.

### T-B7 Assault in lanes (R03)
- **Lanes (new for the squad's own assault, T6):** each assaulter a lane 6 m wide across the
  objective; he clears his own lane, doesn't cut across to go round an obstacle, doesn't bunch.
  Built for the manoeuvre's approach (`SquadTactics.lanes`) and for an ordered assault.
- **Limit of advance (new):** a line 20-30 m past the objective's far side; no one goes past it.
- **Done:** the objective swept, the men consolidated facing out (A3).

### T-B8 Rooms, trenches and bunkers (R06)
- **Built:** building clearing (stack, room by room, floor by floor, flash, frag or charge).
- **New (T9):**
  - A bunker or an enemy-held room with one way in: smoke through the entrance first, then the
    frag from a strong wall, then in.
  - Every cleared room marked: a chem light dropped in its doorway (Demolitions' chem lights), and
    "Clear!" on the net.
  - A trench is cleared like a corridor of rooms: the lead man on the inside wall slicing each
    bend, the second man covering long stretches and overhead.

## 3. Squad (8-12)

The squad: the squad leader (SL, plus an assistant in a big squad) and two or three fire teams.
Three jobs: **assault** (closes and kills), **support** (suppresses), **security** (guards the
flanks and rear, stops reinforcement). A nine-man squad has two teams: security is a pair from
the support team.

### S-C1 On the move (R01)
- The lead team in a wedge; the SL in the middle where he sees both; the second team 5-8 m behind
  in a loose line. Built (Squad `team_offset`, at 12-28 m: **new:** a tighter trail at
  `trail_m` 8 for squads in the open by day; the SL's slot mid-squad when the SL is AI).

### S-C2 React to contact, Battle Drill 1 (R01)
- **Trigger:** the lead team takes fire. It goes to ground and returns fire: the base of fire.
- **The SL** moves up to the base (new: 3-6 s to assess) and chooses by the ground and the odds:
  (a) the second team flanks round the side the enemy sees least, (b) it bounds forward under the
  base's fire, (c) support and assault together. Built: SquadTactics' SUPPRESS_FLANK, the flank
  route and the no-flank fallback to break contact.
- **Done:** the enemy cleared or suppressed and the squad consolidated (T6), or break contact.

### S-C3 The deliberate squad assault (R03)
- **Sequence (new at squad level, T4):**
  1. The support element sets: in position, firing.
  2. Only then the SL's signal: the assault goes (a timeout of 30 s if the support can't set).
  3. The assault bounds in buddy pairs, then in lanes on the objective.
  4. The support shifts, then lifts (T-B6) as the assault closes.
  5. The assault clears to the limit of advance, then all-round security.
- Frontal is fine once the enemy is overwhelmed by suppression; a flank costs time and risks
  friendly fire: SquadTactics scores them (ratio, ground, doctrine).

### S-C4 Near and far ambush at squad level (R05)
- **Near:** the team in the kill zone splits at once into support (cyclic fire) and assault (frags,
  then the charge through: T1); the second team, out of the kill zone, puts fire on the enemy's
  flank; both consolidate on the far side.
- **Far:** the kill-zone team drops and fires with smoke; the second team flanks (built).

### S-C5 Bunkers and trenches: SOSRA (R06)
- **Standalone bunker, a flank possible:** a fire element in hard cover on the firing ports (heavy
  automatic fire so the gunner comes off his sight); smoke in front of the slits; the flank element
  through dead space (the side with no slits); frags in through the slit and the back door; in.
- **A complex (trench, wire, mines; no flank):** SOSRA:
  - **S**uppress: every gun on the bunker and the trench beside it; the marksman on the gunner.
  - **O**bscure: smoke along the slits.
  - **S**ecure: the support element moves up to secure the breach site and kill near threats on
    its flanks.
  - **R**educe: the breach team blows the wire or mines (demolitions).
  - **A**ssault: through the breach into the trench; a team holds the breach and the junctions.
- **Status:** buildings built (CLEAR); **new (T9, P2):** firing-port suppression, smoke on slits,
  the dead-space approach; SOSRA is the platoon's (section 4).

### S-C6 Who goes where
- Half to two thirds of the squad's firepower (the ARs, grenadiers, marksmen) to the base of fire;
  the assault takes the riflemen and a grenadier; the SL where he can see both. Built
  (SquadTactics `elements`); **new:** marksmen and grenadiers weighted to the base.

## 4. Platoon (24-48)

The platoon: a platoon leader, a platoon sergeant, three squads, sometimes a weapons squad. Run by
SideCommand (B2) with its groups as the squads. SOSRA scaled up (R06):

| Element | Job | Role in SideCommand |
|---|---|---|
| Support | Suppress the objective, with the weapons squad and marksmen | `sbf` (built) |
| Breach / assault | Reduce the obstacle, then assault through | `assault` (built), **new:** `breach` when the objective is fortified (wire, mines, a bunker) |
| Secure | Isolate the objective: cut its lateral movement and reinforcement, cover the breach and the trench junctions | **new:** `secure`, on the objective's far flank, facing out and along its lines of reinforcement |

- **Shift and lift by the lead man's marker:** the support shifts when the assault's lead is within
  50 m of the objective and lifts within 25 m (built in SquadOrders by friendlies' real positions,
  which is the marker's job).
- **Status:** support and assault built; secure and breach **new (P1)**.

## 5. Company (~160-240)

A company is three or four platoons and its weapons (mortars, ATGMs, armour attached). In the
code a company is a SideCommand plan: an OperationPlan (attacking) or a DefencePlan (defending)
over its groups.

### E1 The dispersed attack: fix, isolate, starve, concentrate (R07)
- **Trigger:** the defender is dug in with drones and mortars, where mass movement is lethal (a
  fortified village, a town held in strength: the plan's objective marked `fortified`).
- **Phases (new, P2: OperationPlan's `isolate` mode):**
  1. **Fix and attrit:** fires (mortars, artillery: `fire_support_wanted`) pin the garrison.
  2. **Isolate:** small teams (2-3 men, or an ATGM or drone team) infiltrate along tree lines and
     gullies to the objective's flanks and rear, choosing the least-observed approach (not the
     shortest); they set a security zone and interdict its supply and reinforcement routes (the
     roads into it: the zone's road graph).
  3. **Starve:** they hold, killing what comes along those roads, until the garrison is weak: its
     CP (the picture's) falls by half, or no reinforcement has reached it for 10 minutes.
  4. **Concentrate:** only then the groups converge from several axes at once on the decisive point.
- **Done:** the objective taken; the isolating teams become the next phase's screen.

### E2 Defence in depth with a security zone (R08)
- **Behaviour (new, P2: DefencePlan's `security_zone`):** forward of its first line, 1-3 km out
  (scaled to the zone), 2-3 small recon or ATGM elements watch the approaches. They report, call
  fires on what they see, and pull back before they're fixed (never fight to the death). Behind
  them the battle zone: three mutually supporting positions (built: sites on lines). Behind those
  the fires: mortars and artillery, the main killer.
- **Done:** the attacker deploys early or in the wrong direction, under fire.

### E3 The feigned retreat (R04)
- **Behaviour (new, P2):** a company that wants a garrison off its position sends one element at
  it, which then pulls back by bounds (break contact as a weapon). If the garrison follows off its
  posts (the picture shows its men out past the site's radius), a second element waiting out of
  sight pushes in from another side; the first turns at its rally point onto the pursuers.
- **Status:** new. The hostile side uses it too.

## 6. Brigade

A brigade is its companies plus a command element: a brigade HQ, its fires (artillery, the
heavier mortars), its reserve company and its recon.

- **The command element** gives each company plan its axis or its sector, keeps one company in
  reserve, and moves the main effort between companies (the company-level rules of 3.5 one step
  up): the company whose phase stalls gets the fires first and the reserve company second.
- **Status:** new (P3). In the code: SideCommand holding several plans, each over its own groups,
  with a brigade layer above them. Until operations need more than one company it runs one.

## 7. Echelons by side: state forces and terror groups that grow

The Captain's rule (2026-10-22): **terror groups start small** (cells, teams, a few squads) and
**grow** with recruits, money, weapons and territory in the living war, to field platoons or
companies; they shrink when they lose. **Even small they're formidable:** veteran, aggressive,
with local knowledge, ambushes, IEDs, pre-dug positions, hit-and-run. **State forces** (the US,
Eastern Concord) field full echelons from the start.

### 7.1 A faction's force
Each faction in the living war (world_sites.gd's war section) keeps, beside its strength 0-100:

| Field | Grows with | Shrinks with |
|---|---|---|
| `recruits` (men in the pool) | income spent on recruiting; territory held (a zone's men join the holder); rebel support for the Shura | men killed (each kill), men lost when a zone falls |
| `money` | zone income (built: `_income`), cartel trade for Saltline and Kestrel | upkeep (built), recruiting, buying weapons |
| `weapons` (kits) | money spent, loot from wins, captured depots | losses (a kit a man killed) |
| `territory` | zones held (built: the holder rows) | zones lost |

`strength` stays the war's one number for fronts (built) and becomes their sum (Proposed weights in
data/factions.json `force`), so fronts and the new echelons agree.

### 7.2 Echelon by size
A faction's **echelon** is the largest unit it can field, from its men under arms (recruits with a
kit each):

| Echelon | Men under arms | What it fields in a zone |
|---|---|---|
| Cell | under 12 | 1-3 men: IED teams, lookouts, snipers |
| Team | 12-40 | teams of 4-6 |
| Squad | 40-120 | squads of 8-12, a few at once |
| Platoon | 120-400 | platoons of 24-48 (three squads and a weapons team) |
| Company | 400+ | companies: platoons, mortars, technicals |

- **State forces** (`belligerent` or `state` in factions.json: the US, Eastern Concord) start at
  their full echelon (company and up) and never drop below platoon.
- **Terror groups** (Ashen Banner, Valley Shura, Saltline, Kestrel, Highland Front, Black Ridge)
  start at their data's `start_echelon` (a cell or team; the Banner a squad) and move up and down
  the table as their men under arms do, checked each campaign day.
- **What it changes:** garrison sizes (ZoneLevel `garrison_size`, by the holder's echelon:
  a cell's outpost has 2 men, a platoon's the full posts), patrol and QRF sizes (EnemyResponse
  `PATROL_SIZE`, `HUNTER_SIZE`), the reserve pool (EnemyCommand `RESERVE_POOL`), and which plans
  its SideCommand may run (a cell never mounts a company attack).

### 7.3 Small but formidable
Terror groups' doctrine at every echelon (data/doctrines.json per faction, and SquadTactics'
biases, which today only know pmc, regular and insurgent):
- **Veteran:** their kits' combat and discipline stay high when they're small (the few left are
  the hard core): +0.1 combat at cell and team echelon.
- **Aggressive:** assault and flank biases up; they press a contact.
- **Local knowledge:** they know the ground: their ambushes use dead ground and covered routes;
  their spotting of strangers in their own zone is quicker.
- **Ambushes and IEDs:** the share of patrols laying ambushes rises as they shrink (built:
  `AMBUSH_SHARE`, RoadAmbush; RoadsideIeds on routes).
- **Pre-dug positions:** their sites have fighting positions dug (Digging) before the company
  arrives.
- **Hit-and-run:** a terror team fires a heavy first volley, then breaks contact (T-B4) before the
  company can fix it, unless it holds the ratio; at cell and team echelon it always runs.

## 8. Build plan

| Phase | What | Files | Tests |
|---|---|---|---|
| **T1** | Near ambush: the charge-through and consolidation; far ambush unchanged | tactics.gd (new option NEAR_AMBUSH), squad_ai.gd | squad_test: a staged near ambush charges, a far one takes cover |
| **T2** | Break contact by Battle Drill 3: furthest back first, "Moving!" / "Set!", smoke by the grenadier, AR and a rifleman covering, rally point and perimeter | tactics.gd, squad_ai.gd, callouts | squad_test: the order of bounds, the calls, all set at the rally |
| **T3** | Rally points on the move | squad.gd (tasking.rally), squad_ai.gd | squad_test: a rally point named every 150 m |
| **T4** | Fire superiority first: the squad's assault waits for its base to set (30 s timeout) | tactics.gd | squad_test: no manoeuvre move before the base fires |
| **T5** | SBF sectors per man, spreading targets, relocating, shift and lift at squad level | tactics.gd, squad_ai.gd | squad_test: wedges overlap and cover the flanks; lift with the assault close |
| **T6** | Assault lanes, limit of advance, consolidation with all-round security and the ammo check | tactics.gd, squad_ai.gd | squad_test |
| **T7** | Contact reports with the count and what's seen; hostiles shout reports | callouts.gd, squad_ai.gd | squad_test |
| **T8** | Dispersion: cover spots 6 m apart, separation for every side, pinned hostiles crawl | squad_ai.gd, squad.gd | spacing_test |
| **T9** | Smoke before a breach; chem light in every cleared room; bunker ports | squad_ai.gd, tactics.gd | squad_test (rooms) |
| **T10** | Doctrine per faction for the squad's options and spacing (Squad.doctrine set from the faction) | tactics.gd, squad.gd, doctrines.json | squad_test |
| **P1** | Platoon roles: secure and breach; SOSRA for fortified objectives | side_command.gd, operation_plan.gd | side_command_test |
| **P2** | Company: isolate-starve-concentrate, the security zone, the feigned retreat | operation_plan.gd, defence_plan.gd, side_command.gd | side_command_test |
| **P3** | Brigade layer over company plans | side_command.gd | side_command_test |
| **F1** | Faction forces and echelons: recruits, money, weapons, territory; echelon by men under arms; state forces full | world_sites.gd, factions.json, new faction_force.gd | world_sites test (world_test) |
| **F2** | Echelon to the zone: garrison, patrol, QRF and reserve sizes; plans allowed | zone_level.gd hook, enemy_response.gd, enemy_command.gd | missions_test (hot zones keep their sizes at the current default echelon) |
| **F3** | Small but formidable: terror doctrines, ambush share by echelon, hit-and-run | doctrines.json, tactics.gd, enemy_response.gd | squad_test, missions_test |

Order: T1-T10 (team and squad) first, then P1-P3, then F1-F3. Each phase pushed on its own.

**Built 2026-10-22** (SquadTactics, tests/drills_test.gd; squad_test unchanged and passing):
- T1 the near ambush (option NEAR_AMBUSH, SquadAI task "near_ambush");
- T2 break contact as Battle Drill 3 (`_break_contact`);
- T3 rally points (Squad meta "rally");
- T4 fire superiority first (`_flank`'s "Base is set, move!");
- T5 sectors of fire, shift and lift (`sector_aims`, `_base_shift`, `_lifted`);
- T6 lanes, the limit of advance and consolidation (`assault_lanes`, `_consolidate`);
- T7 the contact report's count and what's seen (Callouts `_what_seen`);
- T9 a chem light at each cleared building's door (`mark_cleared`);
- T10 doctrine by faction (`doctrine()` from the men's own; jihadist, guerrilla and cartel biases).

**Built 2026-10-22, platoon to brigade** (SideCommand's plans; side_command_test):
- P1 SOSRA for objectives marked `fortified` (secure and breach roles, smoke on the ports as the
  breach goes in, the assault held for the breach);
- P2 isolate-starve-concentrate for phases marked `isolate`, the feigned retreat for objectives
  marked `lure`, and DefencePlan's security zone (`security_zone`, `threat_dir`);
- P3 BrigadePlan: company plans over their own groups, a reserve company, and fires then the
  reserve to a stalled company.

**Built 2026-10-22, the factions' echelons** (FactionForce, data/faction_force.json; drills_test):
- F1 recruits, kits and money per faction, grown each campaign day from territory and spent on
  men and kits; lost to kills, lost zones and contract defeats; echelon by men under arms; state
  forces fixed;
- F2 garrison sizes and the enemy commander's reserve pool scaled by the holder's echelon over
  its starting one (1.0 at the start); patrols and hunter teams keep their sizes (call 20);
- F3 small terror groups (cell, team) are veterans (+0.1 combat), lie in wait more (70-80% of
  patrols) and hit and run (break contact +0.25, assault -0.1).

Left for later, as calls 12-13 below:
- T8 (dispersion: 6 m cover gaps for every side);
- T9's smoke before a breach and bunker ports;
- T-B5's covering man firing while his buddy bounds.

## 9. Calls made

| # | Call | Why | The alternative |
|---|---|---|---|
| 1 | One set of drills for every side; doctrine and echelon make the differences | The Captain: "all AI in the game" | Per-faction drills |
| 2 | The near ambush is 35 m (hand-grenade range), from R05 | The reels' line between charge and cover | A range by doctrine |
| 3 | Rally points every 150 m, 30-60 m back, named on the net | R04's "point Alpha" | Only at the start |
| 4 | Break contact's furthest man moves first, 10-15 m bounds, "Moving!" / "Set!" | R04 verbatim | Everyone at once (today) |
| 5 | The squad's assault waits up to 30 s for its base to fire | R03: "do not move until the SBF is established and firing" | The commander's 120 s at squad level |
| 6 | SBF wedges of 35°, overlapping, out past both flanks; a shift after 3-5 bursts | R02 | One aim point (today) |
| 7 | Limit of advance 25 m past the objective | R03 | None |
| 8 | Cleared rooms marked with a chem light | R06's panel, with an item the game has | A map marker |
| 9 | Echelon by men under arms (recruits with a kit), five steps cell to company | The Captain's "cells, teams, a few squads ... platoons or companies" | By strength alone |
| 10 | State forces never below platoon; terror groups start at a cell or team (the Banner a squad) | The Captain's rule | Everyone grows |
| 11 | Hot zones keep today's sizes at their factions' starting echelons, so missions_test holds until the war has moved | No surprise retune | Rescaling every zone now |
| 12 | T8 (6 m between men in cover, for every side) waits for a playtest: the Captain tuned spacing by hand (2026-10-14, "they bunched up") and the spacing suite pins today's numbers | Not undoing a tuned feel blind | Changing it now |
| 13 | Smoke before a breach stays for bunkers (one entrance, ports): in a house it blinds the stack as much as the room, and the breach plans (flash, frag, charge) already handle rooms | R06 is about bunkers | Smoke before every door |
| 14 | A near ambush needs the squad to have been moving when it was hit (its centre moved 2 m in the 3 s before), so a squad springing its own ambush never charges | Ambushers aren't ambushed | Any contact under 35 m |
| 15 | Break contact's men go one at a time all the way to the rally point (15 s each at most), not in repeated short bounds | The reel's order and calls, with fewer moving parts | A leapfrog of 10-15 m bounds |
| 16 | The war's `strength` (fronts) stays as it is; the force (men, kits, money) runs beside it and both shrink with losses | The fronts are tuned and world_test pins them | Re-deriving strength from the force now |
| 17 | Starting men: mid-band for the starting echelon (team 25, squad 80); the Banner and Black Ridge start as squads, the Shura, Highland Front, Saltline and Kestrel as teams; US, UK, Canada, Vessmark and Eastern Concord companies, Vantage and Meridian platoons | The Captain's "cells, teams, a few squads" | Everyone a squad |
| 18 | Money a day 4 + 3 a zone (a quarter less per zone where villagers stop paying a predatory group), 2 recruits a zone, 80% spent on a man and his kit (2.5); a man killed costs a recruit and half a kit, a zone lost 15% of both, a company win 6 recruits | Growth over weeks, losses felt at once | Instant swings |
| 20 | Patrols stay pairs and hunter teams 4-6 whatever the echelon: a bigger force fields more of them (bigger garrisons, a bigger reserve pool that sends more teams), not bigger teams | A team is a team; missions_test pins the pairs and the hunter teams | Scaling every team |
| 19 | Pre-dug positions and IEDs by echelon wait: Digging and RoadsideIeds exist but placing them by a faction's size needs the world lane's site layouts | Out of the AI files | Guessing at layouts |
