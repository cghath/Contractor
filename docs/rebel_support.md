# Rebel support (design, proposed)

Captain, 2026-10-16: "rebel support + support upgrade system", inspired by Ghost Recon Wildlands. The
local people back the company when it treats them well. Their backing unlocks local call-ins, and
those call-ins get better over time. This doc proposes the shape. The calls at the end are the
Captain's.

## Already in the code to build on

| Piece | Where | Use |
|---|---|---|
| Standing with the local population | `Economy.locals()`; civilian casualties lower it (`contracts_debrief.gd`, "civilian_rep_locals") | The base of rebel support |
| Villages with people in them | ZoneModules "village"/"town", `PeopleLayer` civilians, `BaseZoneLevel` local sites | Where the rebels live, and where local tasks happen |
| Allied elements under the host's high command | `AlliedTroops` (kits, a Squad, map orders, now driving) | Rebel fighters are an element with a rebel kit |
| Support calls with cooldowns | `Supports.register`, the command menu's Support entries, `HeliSupports` limits per deployment | Where rebel call-ins go |
| Enemy tagging | `EnemyTags` | The lookouts' reports mark enemies the same way a player's radio tag does |
| Contract board, fixers | `Contracts`, `Fixers` | Local tasks can be board jobs |

## Design

**1. Rebel support (0-100, per region).** Each region (coast, inland) has its own local support. It
starts from today's locals standing.
- It rises with what helps the people there:
  - local tasks done (below);
  - treating hurt civilians;
  - giving supplies (food, medical, ammo) from the stash at a village;
  - clearing a site that preys on a village (a checkpoint or an outpost next to it).
- It falls with civilian casualties and with raids on villages. A little more falls with each
  week of heat against the company in the region.
- Tiers at 20, 40, 60 and 80 unlock the call-ins in order.

**2. Local tasks.** These are small jobs from a village. They're offered on the board as "Locals:"
jobs, for low or no cash and paid in support and favours:
- deliver medical supplies to a village;
- escort a farmer's truck;
- clear the checkpoint that taxes the village;
- find a missing villager;
- recover a stolen generator.

Most reuse the mission-variety scenario types (escort, rescue, sabotage, intel grab) with a village
as the site.

**3. Call-ins (command menu: Support > Rebels).** Free, each with a cooldown per deployment, in the
region where they're unlocked.

| Tier | Call-in | What it does |
|---|---|---|
| 20 | Lookouts | Villagers report enemies near you every few minutes. They show as tags (`EnemyTags`), with no radio needed. |
| 40 | Diversion | Rebels open fire at a point you mark; the enemy's QRF and patrols go there. |
| 60 | Rebel fighters | An element of 4-6 rebels in local kit joins you under high command (`AlliedTroops`, a "rebel" kit). |
| 60 | Vehicle drop | A technical is left at a point you mark (`VehicleLayer`). |
| 80 | Mortar | A few rounds on a marked point, after a warning (the rebels' own tube). |

**4. Upgrades (favours).** Each local task pays favours, and one tier's call-ins take favours to
improve:
- Lookouts: more often, and further out.
- Diversion: lasts longer.
- Rebel fighters: more of them, better kit, and a medic.
- Vehicle drop: an armed technical.
- Mortar: more rounds, tighter fall.

Two upgrade levels each. They're bought at the ops desk on a "Locals" page.

**5. What they won't do.** Rebels don't go into hot zones, where the occupiers hold the people
down. They never fight past their region's edge. And they turn away from a company that keeps
killing civilians, below tier 20.

## Build order (proposed)

1. **Support and tiers.** Support per region in `Economy`; what raises and lowers it; a Locals page
   at the ops desk.
2. **Call-ins.** Lookouts and Diversion first (they need no new units), then Rebel fighters and the
   Vehicle drop, then the Mortar.
3. **Local tasks** on the board.
4. **Favours and upgrades.**

## Calls (decided, Captain 2026-10-19)

1. Per region (coast, inland).
2. The call-ins and tiers as in the table.
3. Upgrades take favours, cash and materials (salvage or supplies) together.
4. Local tasks both ways from the start: "Locals:" jobs on the board, and picked up by talking to
   someone in a village.
5. Hot zones: the call-ins work there too, but weaker (longer cooldowns, fewer fighters, fewer
   mortar rounds).
