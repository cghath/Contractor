# Linked zones: the base as a zone, edge transitions, raids

**Status:** design, 2026-10-18/19. Most calls decided by the Captain (six rounds of questions,
2026-10-19 CDT); the few still open carry proposed answers. Nothing built yet.

The Captain's direction (2026-10-18): "the player base needs to be in a zone of its own, one that
can be explored", "raid style excursions should be a thing", "similar to stalker you can go zone
to zone via entries and exits, all the while able to use your supports". And on the base zone
(2026-10-19): "we also get possible hostile patrols or attacks as we cause them issues, causing the
player to need to build up his pmc. this will incentivize moving towards end game".

The idea learns from STALKER's zone transitions: a region is a set of separate maps, each loaded on
its own, joined by marked crossing points at their edges. Walking into one loads the next map and
puts you at its matching entry; what you carry comes with you; the map you left keeps its state for
a while. It feels like one world while each piece stays small enough to run well. Contractor already
has most of the pieces: zones are separate levels made from a definition, the session swaps levels
for every peer, zones save per id, and extraction already knows the zone's edge.

## Already in the code to build on

| Piece | Where | What it gives linked zones |
|---|---|---|
| The base hub | `BaseLevel` (a `CompoundLevel`, 39 m HESCO square, terminals, armory stash on the floor, muster line) | The FOB's contents; the core of the base zone |
| The campaign's base state | `BaseHub` (roster, hiring, base sections; `server_deploy`, `server_end_deployment`) | Prep, squad picks and the settle-up on return stay its job |
| Level swap for the session | `BaseHub.server_switch_level` → `LevelSwitch.load_level`, waits for peers (`SWITCH_WAIT_S`), late joiners follow the host | A crossing is a level swap with a destination entry |
| Zones from a definition | `ZoneDef` (`generate`, `generate_hot`, `normalize`, `insertion`/`extraction`, `EDGE_POINT_IN_M`), `ZoneLevel.configure(def)` | Edge points exist; a link is one more list in the def |
| Per-zone saves | `GameState` (`looted`, `dropped`, `voxel_edits`, `bodies`, `fallen_posts`, `vehicles`), `BaseHub.zone_save_id`, `base_zone_id()` = `fob` | A zone you leave is written and put back when you return |
| Zones fresh each contract | `BaseHub.set_aside_zone_save` (Captain, 2026-10-14; set aside, never deleted) | Replaced by the week-long fade (call 5) |
| Edge exits | `Extraction` (`edge_reach`, foot points within `EDGE_EXFIL_M`, `server_drive_out`, the two-confirm leave-behind rule) | A crossing is an edge exit that leads somewhere |
| The report of what got out | `Contracts.report_from_level`, the extraction report | The cargo list of a crossing |
| Regions and travel | `data/contracts.json` `regions` (coast 1 travel day, base `lhd`; inland 2, base `fob`), `contracts_debrief.gd` | The region map and the clock |
| Support origins | `Supports.origin_for`, `Lhd.install` (LHD offshore, FOB marker on `fob_side`) | Where supports come from in any zone |
| Supports in the zone | `HeliSupports`/`HeliCall`, `AavSupport`, `AlliedTroops` (elements, cooldowns, host high command, map orders), `MotorPool` | What crosses with the squad; the high command tools hired squads reuse |
| Enemy memory | `WorldSites` (holder, grip), `EnemyCommand` (caution per zone), heat (wave 6d) | What drives attacks on the base and reoccupation |
| Streaming | `ZoneLevel` modules in at 260 m / out at 340 m; virtualization designed (`docs/virtualization.md`) | Keeps a big base zone affordable |

## Design

### 1. The base zone

The base stops being a 39 m box and becomes a full zone: a `ZoneLevel` with the FOB built in it
as a module, explorable out to its edges, and a place the enemy comes to as the company makes
trouble for them.

- **Size and ground (decided: a full contract-size zone).** 1920-2304 m (proposed 2304 m), seeded
  from the campaign seed, on its region's terrain (coast: with the LHD offshore, `Lhd.install`
  already places it). It never changes within a campaign.
- **What it holds.**
  - The FOB compound: today's `BaseLevel._build_structures` as a `fob` module type
    (`ZoneModules`), at today's size first. Terminals, stash, muster line, motor pool and stores keep
    their places inside it, so the hub screens don't move. It grows with base upgrades (section 1b).
  - Outside the wire: a helipad, a vehicle park, a firing range and a driving loop.
  - The local area: abandoned sites to scavenge (need-based scavenging and the compound loot boxes),
    a village or two of civilians, roads and trails to the edge crossings.
  - Crossings at its edges into the neighbouring zones (section 2).
- **How it wraps BaseLevel.** A new `BaseZoneLevel extends ZoneLevel` does what `BaseLevel._on_hosted`
  does (spawn the stash, show the roster, `BaseHub.server_level_ready`) and keeps its public face
  (`server_spawn_stash`, `server_collect_stash`, `server_deliver`, `server_show_roster`,
  `server_read_muster_gear`, `muster_soldier`), with `MUSTER_ORIGIN`, `DELIVERY` and `TERMINALS`
  offset by the FOB module's origin. `BaseHub`'s four `is BaseLevel` checks become an `is_base()`
  both answer. `BaseLevel` stays as the fallback for the suites until phase 1 is proven.
- **The stash.** Only items inside the FOB's wire count as stash; items elsewhere in the base zone
  lie where they were dropped, in the base zone's save.
- **Hub screens.** Unchanged; the ops desk adds the region map (section 2), raid launch (section 3),
  base defence and the company's hired squads (section 1b). Deploying by heli from the base stays.
- **Saves.** The base zone keeps the save it already has a name for (`fob`) and is never set aside.

### 1b. Threats to the base and building up the company (decided)

The base area is quiet while nobody is after you. Trouble you cause brings trouble home, which is
the push to build up the PMC and toward the endgame.

- **Hostiles near the base.** None inside 400 m of the wire in normal times. Past 600 m, bandits or
  strays, as an option (off by default). Beyond that, everything comes from heat.
- **Heat-driven tiers.** Heat with a faction (wave 6d) brings, in order: patrols into the far base
  area; probes on the wire; then a full assault, a "defend the base" event the company is warned
  about a day ahead (on the board and the radio). Proposed thresholds: patrols from heat 30,
  probes from 50, assaults from 70, no more than one assault a week.
- **Attacks while the squad is out (decided: a mixture, by the situation).** The radio sends a
  **situation report**: who is attacking, in what strength, what the defences and guards can hold,
  and whether returning is recommended. Small probes resolve off-screen from the defences and guard
  strength (losses: guards, defences, stash items near the wire; never the FOB itself). A big
  assault while the squad is within a few links goes live: the host chooses to come back, and the
  base holds out until they cross in, or until a time limit runs out and it resolves off-screen.
- **Building up (decided: all of these).**
  - **Defences bought** at the ops desk (watchtowers, HESCO extensions, MG and mortar pits,
    sensors), placed at set slots or **freely** by the players with a placement tool (valid ground,
    inside the base's build area).
  - **Hired guards** who man the base while the squad is out (wages, part of the weekly bill).
  - **Hired player-faction squads you command** (decided; inspired by Arma 3's Platoon Commander
    mod): whole AI squads hired into the company, each with its own leader, gear and wages, ordered
    through the host's high command and map orders (the `AlliedTroops` tools: their own `Squad`,
    general orders, map orders). They can guard the base, come on deployments and raids, or be sent
    on their own tasks. This is the company-owned version of allied troops, and the road to the hero
    squad leaders and wave 8's player-built faction.
  - **Base upgrades unlock the endgame**: FOB tiers (bigger wire, more defence slots, more squads)
    unlock hot zones, better supports and the player-built faction (wave 8).

### 2. Zone links

**The region map (decided: every zone linked, neighbours by geography).** Each zone sits on a fixed
region layout (`data/contracts.json` gets a grid position per zone) and links to its 2-4 nearest
neighbours, so you can walk anywhere but far zones take many crossings; heli transport is the
shortcut. All 22 contract zones and 5 hot zones join the graph, the base zone in its region. Coast
and inland join where they meet on the layout. Links are made from the layout, not hand-written:

```
"links": [{"a": "fob", "a_edge": "north", "b": "wadi_farm", "b_edge": "south"}, ...]
```

The ops desk and the map screen draw the graph: each zone, its kind, holder and grip
(`WorldSites.rows()`), what's known of it, and the crossings.

**Crossing points.** Each link puts one **crossing** on each zone's edge (`ZoneDef` "crossings":
`[{"id", "to", "to_crossing", "pos": [x, z]}]`, `EDGE_POINT_IN_M` inside the named side, on a road
or trail end when one reaches it): a marked track, a fence gap, a ford, with the destination's name
on the map. Crossings are also foot extraction points.

**Crossing.** It runs on `Extraction`'s rules, with a destination instead of a debrief:

1. Any player inside a crossing confirms "Move to <zone>". Everyone up and elsewhere blocks; the
   downed, the dead and squadmates away from it warn on the first confirm, and a second within
   `LEAVE_CONFIRM_S` goes without them. Driving into it with the squad aboard is the confirm.
2. A short countdown (proposed 20 s).
3. The host writes the zone being left, builds the cargo report, and calls `server_switch_level`
   with the destination and `"arrive": {"crossing": id, "cargo": report}`.
4. The destination loads (its save if it still remembers, section 2b) and everyone appears at its
   matching crossing in the kit and condition they left with.

**What crosses (decided: everyone and everything in the crossing).** Players; AI squadmates with
their `Inventory` and `Vitals` saves (wounds, tourniquets and pain intact, no free healing); carried
bodies; cuffed HVTs and rescued hostages; everything carried, on MOLLE and in pouches; vehicles
driven in (motor-pool `out` moves to the new zone; captured vehicles become the new zone's); items
set down in the crossing if a vehicle is there to take them. Supports follow too (section 4).
Anyone not at the crossing stays behind in that zone's save.

**Left behind.** A squadmate left in another zone waits there while it remembers; they count as MIA
only if the squad goes home without them (extraction's rule). A downed player respawns with the
squad in their own kit (Captain, 2026-10-14).

**Travel time (decided: hours per link).** On foot 2 game hours per link, by vehicle 1 hour, a heli
hop about 30 minutes. Wounds, bleeding and fatigue tick over that time, so the downed need a medic
before they cross. Three or four links on foot cost about a campaign day: when the clock passes
midnight, `Economy.advance_days(1)` runs as at the base (wages, recovery, the board, WorldSites
ticks). The real-time cost is the load behind the loading screen.

### 2b. Zone memory (decided: fades over a week)

A zone you leave remembers you, then fades back to fresh. This replaces "fresh each contract"
(2026-10-14):

- Bodies and dropped gear clear after 2-3 campaign days.
- Voxel damage and cleared sites last 7 days; meanwhile the enemy reoccupies through `WorldSites`
  grip and `EnemyCommand` reserves, so a site you cleared yesterday may be manned again.
- After 7 days the zone is fresh: its save is set aside (`GameState.set_aside`, never deleted).
- The base zone never fades. World-site state (holder, grip, caution) is the campaign's and
  persists as now.

Each zone save gets a `"left_day"`; the fade runs on load and in `Economy.advance_days`.

### 3. Raid-style excursions

A **raid** is going out without a contract to scavenge, hit sites for loot and intel, and come back.

- **Launching.** Walk or drive out of a base crossing, or pick "Raid" at the ops desk for a heli
  insertion (paid). Squad pick, ready-up and loadout as for a contract: `server_deploy` with a
  `zone_kind` of `"raid"` (today's debug `no_contract` path made real), so casualties, respawns and
  MIA rules all apply.
- **Rules (decided: lean and risky).** 2 free respawns, bought past that; supports paid from the
  bank; no pay or salvage share; heat and standing change for what you hit (a faction's sites cost
  standing with it and its allies); zones raided again soon are alert (`caution` persists).
- **Extraction.** Home is the base: cross back into the base zone and in through the wire, or call
  the heli from anywhere (paid). A short debrief on arrival: intel to turn in or sell, reputation and
  heat, casualties through `BaseHub.server_end_deployment`.
- **What you keep (decided: all that comes home).** Everything carried, driven or flown home. A wiped
  raid leaves its gear on the bodies in that zone, recoverable while the zone remembers (about a
  week, section 2b; recovery contracts already exist).
- **Raids and contracts.** A raid can't start during a contract deployment; that deployment can cross
  zones itself (section 3b).

### 3b. Contracts across zones (decided: both)

- Any contract lets the squad leave its zone and come back. Its objectives stay live in their own
  zone, its clock runs, and it ends at its extraction or when the squad gets home.
- New contract types spread their objectives over 2-3 linked zones (a convoy chase, a manhunt that
  moves, a supply line to cut at several points). They're added to `data/contracts.json` like the
  mission-variety types, with each objective naming its zone.

### 4. Supports across zones (decided: everything follows)

Supports come from the company, so they're usable in every zone, including the base area and raids,
and they come with the squad when it crosses.

- **Origins.** In a linked zone the support origin (`Supports.origin_for`) sits on the edge facing
  the base on the graph, instead of `fob_side`. In the base zone it's the FOB's helipad.
- **Helicopters.** A heli that is airborne or loitering when the squad crosses arrives over the new
  zone a minute after them (re-made by `HeliSupports` from its call's state at the entry edge). One
  that is landing or lifting off finishes that first. Cooldowns and "lost this op" carry across (they
  belong to the deployment).
- **Heli transport (decided: between zones, and local transport everywhere).** The transport call
  can take a zone on the region map: the squad boards, the crossing happens in the air (about 30 game
  minutes), and it lands at the destination's insertion LZ. Paid per flight. Transport inside a zone
  is no longer hot-zones-only.
- **The AAV, motor-pool vehicles and allied elements** cross with the squad: those in the crossing
  ride across; the AAV and allied elements out on other orders arrive at the same crossing shortly
  after, keeping their orders (proposed: within 2 minutes of game time; elements more than a link's
  travel away are released instead). The host's high command and map orders work the same in every
  zone. Hired company squads follow the same rules.

### 5. Co-op and host constraints

- **One zone at a time for now (decided: split squads later, with dedicated servers).** All peers
  are in the same level; a crossing moves everyone, which is why it needs the whole squad at the
  point. Plan for a split now: keep zone state in its save and the excursion's zone list, not in "the
  one live level", so a dedicated server can later hold two zones at once.
- **Who confirms.** Any player inside the crossing (2026-10-14).
- **Late joiners** join the zone the host is in (LevelSwitch's handshake already sends it), at the
  last crossing used, in their own kit. Bots never host (2026-10-14).
- **Switch timeouts.** A slow peer holds the switch up to `SWITCH_WAIT_S`, then catches up (B-04).
- **Saving while out (decided: resume where you were).** The host's quick save and quit writes the
  current zone and the excursion's state (its zone list, supports out, clock); loading resumes in the
  zone the squad was in, at the last crossing they came through. Today a mid-deployment load ends the
  deployment at the base; that changes for both raids and contracts.

### 6. Performance and streaming

- **Load times.** A crossing is a level swap (terrain, collision, coarse meshes: `generate_ms`).
  Proposed target: under 5 s for a contract zone, 10 s for a hot zone on the Captain's machine,
  measured in phase 1. If it's over, pre-generate the neighbour's terrain on a thread while the squad
  is in the crossing's edge band (the definition is known by then).
- **Saves.** The week-long fade (section 2b) keeps saves from growing without end.
- **The base zone.** The FOB module always streams; the rest streams like any zone. During an
  assault it costs what a contract zone does.
- **Virtualization.** Not needed for crossings, since one zone is live at a time. When it lands
  (`docs/virtualization.md`), profiles make a zone you left keep moving, carry patrols toward the
  base, and are what a dedicated server would run for a second zone.

## Calls for the Captain

**Decided (Captain, 2026-10-19 CDT):**

1. Base zone: a full contract-size zone with scavenging and a local area; hostile patrols and attacks
   as the company causes trouble, pushing it to build up toward the endgame.
2. Hostiles near the base: none close in normal times, far strays as an option, and the base can be
   attacked (defend-the-base events), escalating in heat-driven tiers.
3. Building up: bought defences (set slots and free placement), hired guards, base upgrades that
   unlock the endgame, and hired player-faction squads under the host's high command (inspired by
   Platoon Commander).
4. Region map: every zone linked to its 2-4 geographic neighbours; heli transport is the shortcut.
5. Zone memory: fades over a week (bodies and gear 2-3 days, damage and cleared sites 7 days with
   reoccupation, then fresh).
6. Crossing cargo: everyone and everything in the crossing.
7. Travel time: 2 h per link on foot, 1 h by vehicle, about 30 min by heli; can add up to days.
8. Raids: lean and risky; keep all that comes home.
9. Supports: everything follows, a loitering heli included; heli transport between zones and local
   transport everywhere.
10. Split squads: later, with dedicated servers; plan the state for it now.
11. Save while out: resume in the zone, at the last crossing.
12. Base attacked while out: a situation report with a return recommendation; small probes resolve
    off-screen, big assaults near enough go live and hold out for the squad.
13. Contracts: can be left and returned to, plus new multi-zone contract types.
14. Build order: the base as a zone first.

**Still open (proposed answers):**

15. **Base zone size.** Proposed: 2304 m.
16. **Heat thresholds for base threats.** Proposed: patrols at 30, probes at 50, assaults at 70; at
    most one assault a week, warned a day ahead.
17. **Crossing countdown.** Proposed: 20 s.
18. **Followers' catch-up.** Proposed: supports on other orders arrive within 2 game minutes;
    allied elements more than a link away are released.
19. **Hired squads.** Proposed: 4-8 men each, a squad leader from the roster or hired with them,
    wages at the roster's rates, up to 1 per FOB tier to start.

## Build order (proposed)

1. **LZ-1 The base as a zone.** `fob` module type; `BaseZoneLevel` with BaseLevel's public face;
   `is_base()`; the base zone from the campaign seed; helipad, vehicle park, range. Deploying is
   unchanged. Measure load time.
2. **LZ-2 Crossings and the region map.** The region layout and links, `"crossings"` in `ZoneDef`,
   the crossing as an `Extraction` point kind, `server_switch_level` with `"arrive"`, cargo across,
   travel hours on the clock, zone memory and its week-long fade. Base ↔ one zone first, then all.
3. **LZ-3 Supports across zones.** Origins facing the base, followers crossing (heli, AAV, allied
   elements, vehicles), cooldowns per deployment, heli transport between zones and everywhere.
4. **LZ-4 Raids and contracts across zones.** The `"raid"` kind, its rules and debrief; contracts
   left and returned to; save and resume while out.
5. **LZ-5 The base's local area and its threats.** Scavenging sites and villages; heat-driven
   patrols, probes and assaults; the situation report; off-screen resolution.
6. **LZ-6 Building up the company.** Defences (slots, then free placement), hired guards, hired
   squads under high command, FOB tiers unlocking the endgame.
7. **LZ-7 Multi-zone contract types**, and the neighbour's terrain pre-generated if LZ-1's load
   numbers need it.

LZ-1 stands alone. LZ-2 needs LZ-1. LZ-3 and LZ-4 both need LZ-2 and can run side by side. LZ-5 needs
LZ-1 and wave 6d's heat; LZ-6 needs LZ-5's attacks to matter; LZ-7 needs LZ-4. Split squads on a
dedicated server and virtualization are separate and wait on nothing here.
