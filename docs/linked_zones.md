# Linked zones: the base as a zone, edge transitions, raids

**Status:** design proposal, 2026-10-18, for the Captain's sign-off. Nothing built yet.

The Captain's direction (2026-10-18): "the player base needs to be in a zone of its own, one that
can be explored", "raid style excursions should be a thing", "similar to stalker you can go zone
to zone via entries and exits, all the while able to use your supports".

The idea learns from STALKER's zone transitions: a region is a set of separate maps, each loaded on
its own, joined by marked crossing points at their edges. Walking into one loads the next map and
puts you at its matching entry; whatever you carry comes with you; the map you left keeps its
state. It feels like one world while each piece stays small enough to run well. Contractor already
has most of the pieces: zones are separate levels made from a definition, the session swaps levels
for every peer, zones save per id, and extraction already knows the zone's edge.

This page sets out what's in the code to build on, the design, the calls the Captain still has to
make (each with a proposed answer, so a yes is enough) and a build order.

## Already in the code to build on

| Piece | Where | What it gives linked zones |
|---|---|---|
| The base hub | `BaseLevel` (a `CompoundLevel`, 39 m HESCO square, terminals, armory stash on the floor, muster line) | The FOB's contents; it becomes the core of the base zone |
| The campaign's base state | `BaseHub` (roster, hiring, base sections; `server_deploy`, `server_end_deployment`) | Prep, squad picks and the settle-up on return stay its job |
| Level swap for the whole session | `BaseHub.server_switch_level` → `LevelSwitch.load_level`, waits for peers (`SWITCH_WAIT_S`), late joiners follow the host's level | A zone crossing is a level swap with a destination entry |
| Zones from a definition | `ZoneDef` (`generate`, `generate_hot`, `normalize`, `insertion`/`extraction` lists, `EDGE_POINT_IN_M`), `ZoneLevel.configure(def)` | Edge points already exist; a link is one more list in the def |
| Per-zone saves | `GameState` (`zone_id`, `looted`, `dropped`, `voxel_edits`, `bodies`, `fallen_posts`, `vehicles`), `BaseHub.zone_save_id` (`<campaign>__<zone>`), `base_zone_id()` = `fob` | A zone you leave can be written and put back when you return |
| Zones fresh each contract | `BaseHub.set_aside_zone_save` (Captain, 2026-10-14; never deleted) | The rule that decides when a linked zone is fresh (call 4) |
| Edge exits | `Extraction` (`edge_reach`, `at_edge`, foot points within `EDGE_EXFIL_M`, `server_drive_out` at `VEHICLE_OUT_M`, the two-confirm leave-behind rule) | A crossing is an edge exit that leads somewhere instead of ending the deployment |
| The report of what got out | `Contracts.report_from_level`, `Extraction` report (players, squad, left_behind, bodies, items, driven_out, vehicles) | Exactly the cargo list of a crossing |
| Regions and travel | `data/contracts.json` `regions` (coast: 1 travel day, base `lhd`; inland: 2, base `fob`), `contracts_debrief.gd` adds `travel_days` | The region map and the clock cost of moving |
| Support origins | `Supports.origin_for` (registered `lhd`/`fob` origin, else the map edge nearest the squad), `Lhd.install` (LHD on coastal zones, FOB marker on the "fob_side" inland) | Where helis, the AAV and allied troops come from in any zone |
| Supports in the zone | `HeliSupports`/`HeliCall` (resupply, transport, extraction), `AavSupport`, `AlliedTroops` (two elements, cooldowns, host high command), `MotorPool` (`server_bring`, `server_return`, "out" zone) | What has to carry over or be re-called across a crossing |
| Streaming | `ZoneLevel` modules in at 260 m, out at 340 m, one per 0.25 s; virtualization designed (`docs/virtualization.md`) | Keeps a big base zone and bigger linked zones affordable |

## Design

### 1. The base zone

The base stops being a 39 m box and becomes a zone of its own: a `ZoneLevel` with the FOB built in
it as a module, explorable out to its edges.

- **Size and ground.** A contract-sized zone (proposed 1536 m square, `ZoneDef.normalize` as any
  other), terrain from its region's preset (inland FOB: the region's preset; coast: a coastal
  lowland with the LHD offshore, `Lhd.install` already places it). Seeded from the campaign seed, so
  every campaign has its own base ground and it never changes within one.
- **What it holds.**
  - The FOB compound at the centre: today's `BaseLevel._build_structures` moved into a `fob` module
    type (`ZoneModules`), at its current size first, bigger later (wave 7 world pass: barracks,
    helipad, range). Terminals, armory stash, muster line, motor pool and stores stay where they are
    inside it, so nothing about the hub screens moves.
  - A helipad and a vehicle park outside the wire (where helis land for insertion, where motor-pool
    vehicles stand ready to drive out).
  - A firing range and a driving loop (test kit and vehicles before a contract).
  - Around the FOB, a quiet ring (proposed 400 m: no hostiles ever) and beyond it the **local
    area**: a village or two of civilians (the Salvage Union's people, traders), a few abandoned
    sites with low-grade scavenging (need-based scavenging already exists), and rare low-threat
    hostiles past 600 m (bandits, a stray patrol: proposed off by default, call 2).
  - Exits at its edges into the region's other zones (section 2).
- **How it wraps BaseLevel.** `BaseLevel` today is a `CompoundLevel`; the base zone is a `ZoneLevel`.
  Proposed: a new `BaseZoneLevel extends ZoneLevel` that does what `BaseLevel` does in its
  `_on_hosted` (spawn the stash, show the roster, call `BaseHub.server_level_ready`) and keeps its
  public face (`server_spawn_stash`, `server_collect_stash`, `server_deliver`, `server_show_roster`,
  `server_read_muster_gear`, `muster_soldier`), with the FOB module's origin as the offset for
  `MUSTER_ORIGIN`, `DELIVERY` and `TERMINALS`. `BaseHub` asks `level() is BaseLevel` in places; those
  become a small `is_base()` check that both answer. `BaseLevel` stays as the fallback (and for the
  suites that load it) until phase 1 is proven, then goes.
- **The stash outside the armory.** Today "anything left lying in the hub counts as stash". In a
  1.5 km zone that would bank a rifle dropped in a field. Proposed: only items inside the FOB's wire
  count as stash; items elsewhere in the base zone stay where they lie in the base zone's save, like
  any zone.
- **Hub screens.** Unchanged: the terminals still open `BaseUI` pages. The ops desk gains the
  **region map** (section 2) and the raid launch (section 3). The contract board is unchanged.
  Deploying by helicopter from the base (today's way) stays: the briefing and insertion choice work
  as now. Walking or driving out of a base exit is the new, second way.
- **Saves.** The base zone uses the save it already has a name for (`base_zone_id()` = `fob`), and
  is never set aside (`set_aside_zone_save` already refuses the FOB's). Its voxel edits, dropped
  items, parked vehicles and bodies persist for the campaign.

### 2. Zone links

**The region map.** Each region (coast, inland) becomes a small graph of zones, kept in
`data/contracts.json` beside the zones:

```
"links": [
  {"a": "fob", "a_edge": "north", "b": "wadi_farm",   "b_edge": "south", "travel_min": 20},
  {"a": "fob", "a_edge": "east",  "b": "red_mesa",    "b_edge": "west",  "travel_min": 30},
  {"a": "red_mesa", "a_edge": "north", "b": "pass_hot", "b_edge": "south", "travel_min": 40}
]
```

Proposed shape: the base zone in the middle, 2-4 contract zones linked to it, hot zones linked one
step further out (you cross a contract zone to reach one on foot, or fly straight there). The coast
and inland regions link to each other through one crossing each way (the travel_days between them
stays). The ops desk and the map screen draw the graph: each zone, its kind, its holder and grip
(`WorldSites.rows()`, already sent to clients), what's known of it, and the crossings.

**Crossing points.** Each link puts one **crossing** on each zone's edge: a named point
(`ZoneDef` "crossings": `[{"id", "to", "to_crossing", "pos": [x, z]}]`, placed by `_ensure_edge`'s
rules, `EDGE_POINT_IN_M` inside the edge on the named side, on a road or trail end when one reaches
that side). On the ground it's a marked track or road end with a sign, a gap in the fence, a dry
ford; on the map, an icon with the destination's name. A zone's crossings are also its foot
extraction points (they already are edge points); not every edge point is a crossing.

**Crossing.** It runs through `Extraction`'s rules, with a destination instead of a debrief:

1. A player inside a crossing confirms "Move to <zone>" (any player, the co-op rule of
   2026-10-14). The same check as extraction runs: everyone up and elsewhere blocks; the downed and
   the dead outside it, and squadmates away from it, warn on the first confirm, and a second within
   `LEAVE_CONFIRM_S` goes without them (they stay in the zone being left: section "left behind").
2. A short countdown (proposed 20 s, not extraction's 90: nobody has to come to you).
   Vehicles: driving into the crossing with the squad aboard is the confirm, as `server_drive_out`.
3. The host writes the zone being left (`GameState.save_zone`), builds the cargo report
   (`report_from_level`'s list: players, squad, bodies carried, HVTs, items, vehicles in the
   crossing), and calls `server_switch_level` with the destination's level info and a new
   `"arrive": {"crossing": id, "cargo": report}`.
4. The destination loads (its save, or fresh: call 4), spawns everyone at its matching crossing
   (players spread as `SPAWN_SPREAD_M`, vehicles on the road behind them), in the kit and condition
   they left with, and its supports origin, enemy response and objectives come up as on insertion.

**What crosses with you.**

| Thing | Crosses? | How |
|---|---|---|
| Players | Yes | Their gear, as `server_switch_level` already keeps it |
| AI squadmates in the crossing | Yes | Their `Inventory` and `Vitals` saves, as the roster does on deploy |
| Downed or wounded (carried in, or walking) | Yes | `Vitals` saved whole: the bleed, tourniquets and pain go with them; no free healing on the way |
| Bodies carried in | Yes | As `body_record`, put down beside the carrier |
| Cuffed HVTs, rescued hostages | Yes | The HVT record; a contract HVT counts at the contract's extraction only |
| Items carried, on MOLLE, in pouches | Yes | They're on the soldier |
| Items set down in the crossing | Yes, if a vehicle is there to take them | Otherwise they stay (no carrying a stash across by hand dropping) |
| Motor-pool vehicles in the crossing | Yes | `Vehicle.to_save` with the pool id; `MotorPool` "out" moves to the new zone |
| Other vehicles (captured technicals) | Yes, if the squad drives them | Same, as a zone vehicle in the new zone's save |
| Helicopters | No | They don't cross edges; they're re-called (section 4) |
| Allied elements | Yes if ordered "follow me" and inside 150 m of the crossing | Else they stay and RTB (section 4) |
| Squadmates and players left behind | No | They stay in the zone left, as the extraction leave-behind rule; their zone's save keeps them |

**Left behind across zones.** A squadmate left in another zone is not MIA yet: they wait where
they were (the zone save keeps them, as recovery targets already do), and going back for them is a
crossing away. They count as MIA only if the squad goes home without them (extraction's rule,
unchanged). A player left downed in another zone respawns with the squad (respawn in own kit,
Captain 2026-10-14); their body isn't left behind, the same as today.

**Travel time.** Crossing costs campaign time, not real time: each link's `travel_min` (proposed
20-40 game minutes) moves the in-game clock on (time of day, when wave 7 has one), and bleeding,
pain and fatigue tick over that span on the way (the downed need a medic before they cross, or
arrive worse). It never advances campaign days by itself; days still pass at the debrief and the
base, as now. Real-time cost is the load: a few seconds behind the loading screen.

**Saves while out.** Today a campaign loaded mid-deployment ends that deployment at the base. With
crossings, the host's quick save and quit while out writes the current zone and every zone the
excursion has touched; loading one resumes in the zone the squad was in, at the crossing they last
came through (proposed; call 7).

### 3. Raid-style excursions

A **raid** is going out without a contract: leaving the base (by an exit, by vehicle, or by a heli
insertion at a cost) into the region's linked zones to scavenge, hit sites for loot and intel, and
come back.

- **Launching.** Walk or drive out of a base exit, or pick "Raid" at the ops desk (heli insertion
  into any linked zone, paid: the transport price). The squad pick, ready-up and loadout work as
  for a contract (`server_deploy` with `no_contract`, which already exists for debug, made real with a
  `zone_kind` of `"raid"`); the roster's deployment record is made so the squad's casualties,
  respawns and MIA rules all apply.
- **What's out there.** The linked zones as generated, with their garrisons, patrols and
  compound loot (rarity loot boxes and intel boxes are on the 2026-10-16 list). No objectives, no
  pay, no employer, no support budget from a contract.
- **Risk.**
  - Respawns: half a contract zone's (proposed 2), bought past that.
  - Supports are paid in full from the company's bank (no contract budget to draw on).
  - Hitting a faction's sites on a raid raises heat with them and costs standing, as killing their
    men on a contract against them does; hitting your employer's friends costs more.
  - The enemy's response is the zone's own (`EnemyResponse`, `EnemyCommand` reserves); raiding the
    same zone again soon finds it alert (`caution` already persists per zone).
- **Extraction.** Home is the base: walk or drive back through a crossing into the base zone and
  through the FOB's gate, or call the heli to extract from anywhere (paid). Arriving inside the
  wire ends the raid: a short debrief (no pay, no salvage share since nobody else owns it: the squad
  keeps everything carried in), reputation and heat changes, casualties settled by
  `BaseHub.server_end_deployment`.
- **What you keep.** Everything that comes home: all items, vehicles taken, intel (turned in or sold
  at the debrief as now). Nothing is kept if the squad never comes home: a wiped raid is MIA for
  everyone left, and their gear is in the zone they fell in, to recover (recovery contracts already
  exist).
- **Raids and contracts together.** A contract's deployment can also cross zones: a contract zone
  linked to its neighbours lets the squad leave it on foot and come back, and still finish it. The
  contract's clock keeps running, its objectives stay live only in its own zone, and it ends at its
  extraction or when the squad gets home. A raid can't start while a contract deployment runs; it
  *is* the deployment then.

### 4. Supports across zones

Supports come from the company, not from the zone, so they're available in every zone the squad
is in, including the base zone's local area and on raids.

- **Origins.** `Supports.origin_for` already picks the LHD, else the FOB marker, else the nearest
  edge. Proposed: in a linked zone the FOB origin sits on the edge facing the base on the region
  graph (the side its link to the base, or to the next zone toward the base, comes in), not
  `fob_side`. In the base zone itself the origin is the FOB's helipad: helis lift from there.
- **Helicopters.** They don't follow across an edge. A heli on a call when the squad crosses
  finishes or aborts that call (resupply: lands and leaves; transport: drops the squad where it is)
  and the next call in the new zone comes from its origin, as now. Cooldowns and "lost this op"
  carry across (they're the deployment's, not the zone's). New: **transport between zones** — the
  transport call can take a destination on the region map instead of a map marker: the heli lands,
  the squad boards, and the crossing happens in the air (the loading screen), landing at the
  destination's insertion LZ. That's the fast way across the graph, paid per flight. Transport is
  still hot-zones-only today (Captain); proposed: zone-to-zone transport allowed anywhere, local
  transport inside a zone stays hot-only (call 5).
- **The AAV.** It's a vehicle: with the squad aboard and driven into a crossing it crosses like any
  motor-pool vehicle. Left behind under AI crew, it's ordered home: it drives to the nearest edge
  toward the base and is gone, then re-callable in the new zone (its cooldown, not a new price).
  Ordered "follow" when the squad crosses on foot, it crosses with them (proposed).
- **Allied troops.** An element on "follow me" within 150 m of the crossing when it fires crosses
  and arrives behind the squad (its `Squad` saved as its members' records). Any other element stays
  in its zone and RTBs: it's released, and its slot's cooldown starts. The host's high command
  (support-menu orders, map orders) works the same in every zone. Called fresh in a new zone they
  come from that zone's origin.
- **Motor pool.** Vehicles taken out of the base zone's vehicle park drive across like anything
  else; `MotorPool` "out" holds the zone id they're in now, and `server_reconcile` already handles a
  vehicle whose zone isn't loaded.

### 5. Co-op and host constraints

- **One zone at a time for the session.** All peers are in the same level, always: a crossing
  moves everyone, as `server_switch_level` does today. Splitting the squad across zones would mean
  the host simulating two levels at once (or a dedicated server); out of scope (call 6). That's why
  crossing needs the whole squad at the point, with the leave-behind confirm for those who aren't.
- **Who can confirm.** Any player inside the crossing, as extraction (Captain, 2026-10-14).
- **Late joiners.** A client joining while the squad is out joins in the zone the host is in
  (LevelSwitch's handshake already sends the host's level). They spawn at the last crossing used,
  in their own kit.
- **A player who drops out mid-zone.** Their character stays as today; if a crossing happens while
  they're gone they move with the squad (their stand-in or body as the leave-behind rule says).
- **Bots never host.** A human hosts (2026-10-14), so the host is always a player inside the squad.
- **Switch timeouts.** A peer slow to load holds the switch up to `SWITCH_WAIT_S`, then the switch
  goes without them and they catch up (B-04), the same as deploying.

### 6. Performance and streaming

- **Load times.** A crossing is a level swap: terrain heights, collision and the coarse meshes
  (`generate_ms`). Today that's measured per zone; proposed target: under 5 s for a contract zone and
  under 10 s for a hot zone on the Captain's machine, measured in phase 1 before anything is built
  on top. If it's over, pre-generating the neighbour's terrain on a thread while the squad walks to
  the crossing is the fix (the definition is known as soon as they're in its edge band).
- **Zone saves grow.** A zone revisited many times keeps bodies and items. Bodies already leave a
  zone's save after a while (`fallen_posts` keeps what fell); proposed: dropped items past 3
  campaign days outside a building decay out, and bodies leave after 2.
- **The base zone.** Its FOB module is always streamed (it's where the host spawns); its local area
  streams like any zone. With nothing hostile near the FOB, its cost is the terrain and a few
  civilians: lighter than a contract zone.
- **Virtualization.** Linked zones don't need it to work: only one zone is ever live. When it lands
  (`docs/virtualization.md`), profiles are what lets a zone you left keep moving (a patrol that was
  hunting you has gone further when you come back) and what the faction simulation moves between
  linked zones. Until then a zone left is frozen as saved.

## Calls for the Captain (proposed answers)

1. **Base zone size and look.** Proposed: a 1536 m zone on the region's terrain, the FOB at its
   centre at today's size first (bigger in the wave 7 world pass), helipad, vehicle park and range
   outside the wire, one or two civilian villages in the local area.
2. **Hostiles near the base.** Proposed: none inside 400 m ever; past 600 m, bandits and strays off
   by default, switched on later as an option (or by heat: a faction you've angered probes the base
   area; never attacks the FOB itself, as the LHD is never attacked).
3. **The region map.** Proposed: the base in the middle, 2-4 contract zones linked to it, hot zones
   one step further; one link between coast and inland. Today's 22 contract zones stay on the board;
   the linked set is the ones nearest the base (the rest are fly-in only).
4. **Fresh or remembered.** Today every contract finds its zone fresh (Captain, 2026-10-14).
   Proposed: within one deployment or raid a zone is remembered (cross out and back and it's as you
   left it: that's the point of linked zones); a new deployment or raid finds it fresh as now, except
   the base zone and the world-site state (`WorldSites` holder and grip, `EnemyCommand` caution),
   which already persist. Saves are set aside, never deleted, as now.
5. **Heli transport between zones.** Proposed: allowed from any zone (paid per flight, the transport
   price), landing at the destination's insertion LZ; transport within a zone stays hot-zones only.
6. **Split squads.** Proposed: no. The whole session is in one zone; those who don't come are left
   behind (two confirms), as at extraction.
7. **Saving while out.** Proposed: quick save and quit while out resumes in the zone the squad was
   in, at its last crossing (today a mid-deployment load ends the deployment at the base). Needs the
   campaign to keep the excursion's zone list; the "fresh each contract" rule still applies on the
   next one.
8. **Raid rules.** Proposed: 2 free respawns, supports paid from the bank, no pay or salvage share,
   keep everything brought home, heat and standing changes for what you hit, a short debrief on
   arrival inside the wire.
9. **Crossing time.** Proposed: 20-40 game minutes per link (moves the time of day, wounds tick over
   it), no campaign days; a 20 s countdown at the crossing.
10. **Contract zones crossed out of.** Proposed: yes, a contract's squad can leave its zone and come
    back; its objectives stay live in its own zone, its clock runs, it ends at its extraction or on
    reaching home.

## Build order (proposed)

1. **LZ-1 The base as a zone.** `fob` module type from `BaseLevel._build_structures`;
   `BaseZoneLevel` with BaseLevel's public face; `BaseHub` checks `is_base()`; the base zone's
   definition from the campaign seed; helipad and vehicle park. Deploying is unchanged (heli from the
   ops desk). Measure load time here. Suites: the base and campaign suites, smoke.
2. **LZ-2 Crossings and the region map.** `"links"` in contracts.json, `"crossings"` in `ZoneDef`,
   the crossing as an `Extraction` point kind with a destination; `server_switch_level` with
   `"arrive"`; cargo carried across (players, squad, carried bodies and HVTs, vehicles); zones
   remembered within one deployment (call 4); the map and ops desk draw the graph. Base ↔ one
   contract zone first, then the rest.
3. **LZ-3 Supports across zones.** Origins facing the base on the graph, cooldowns and losses kept
   per deployment across crossings, the AAV and allied elements following on "follow", heli
   transport between zones.
4. **LZ-4 Raids.** The `"raid"` deployment kind, launching on foot/vehicle/heli, its respawns and
   paid supports, the raid debrief on arrival home, heat and standing for what was hit.
5. **LZ-5 The base's local area.** Villages, scavenging sites, the range and driving loop; hostiles
   past 600 m behind an option (call 2).
6. **LZ-6 Saving while out and polish.** Resume in the zone the squad was in (call 7), save decay
   for revisited zones, the neighbour's terrain pre-generated while walking to a crossing if the
   phase 1 load numbers need it.

LZ-1 stands alone. LZ-2 needs LZ-1 (the base is where the links start). LZ-3 and LZ-4 both need
LZ-2 and can run side by side (supports files vs. the deployment and debrief). LZ-5 needs only
LZ-1 and can run any time after it. Virtualization (`docs/virtualization.md`) is separate; it
makes left zones live later but nothing here waits on it.
