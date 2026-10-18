# Wave 6 groundwork: factions

**Status (2026-10-18):** 6a built (tiers with pay by tier, Hostile offers no work, ripple, decay,
side lockout: `Economy`, `Contracts`, `factions.json` "reputation_rules"). 6b started: enemy kits as
data (`Kits`, `factions.json` "kits"), a placeholder regional army ("Federal Army", Eastern-bloc
kit, woodland), contracts against any kitted faction switch the zone's patrols, hunters, QRF waves
(which stayed Black Ridge's before) and, for data kits, garrisons; Black Ridge carries a captured
M4 (Captain: factions known to field AR-pattern rifles use them). Still open in 6b: the real faction
set (call 4 below), regional weapon art (Chinese, Iranian), a garrison already spawned before its
contract went live keeps the militia kit. Groundwork below as written. Wave 6 is next once the Oct 18 open
items are in (Captain, 2026-10-18). This page collects what's already decided, what the code already
has to build on, the calls the Captain still has to make (each with a proposed answer, so a yes is
enough), and a build order. The plan's own scope is in [build_plan.md](build_plan.md) (Wave 6) and
[ChrisPlan_handoff.md](ChrisPlan_handoff.md#wave-6-factions-blocked); the rules come from
[mission_brainstorm.md](mission_brainstorm.md).

## Already decided (mission_brainstorm.md)

- **Five reputation tiers per faction:** Hostile, Distrusted, Neutral, Trusted, Allied. Each step up
  unlocks better contracts, pay, gear, vehicles and supports. Hostile factions send hunters.
- **Ripple:** rep gained with a faction slightly raises it with that faction's allies and lowers it
  with its enemies (the US, GB and Canada move together).
- **Decay:** rep drifts back toward Neutral when the squad stops working for a faction; Allied needs
  only occasional jobs to keep.
- **Side lockout:** work for one faction locks the squad out of its enemies' contracts for a while
  (proposed there: the current deployment plus a few campaign days).
- **Allied troops:** joint operations where a friendly unit fights alongside as its own AI group. The
  player can request help but can't command it.
- **Heat and bounty hunters:** angering a faction builds heat; high heat brings generic hunter teams
  into missions near its territory; at the top, persistent named hunter squads that remember the squad.
- **Rival contractor teams** are a recurring enemy.
- **Persistent world:** cleared outposts stay cleared, destroyed buildings stay destroyed; over campaign
  time damage is repaired and lost positions reoccupied.
- **Faction simulation:** between missions factions attack each other, take ground, build and lose
  outposts. **War-driven contracts** come out of it (retake the outpost, raid ahead of the push).
- **Contract sources:** a public board per region, plus fixers for special jobs as rep grows.
- **Enemy supports:** better-equipped factions call mortars, armed helicopters or drones at high alert.
- **Suicide bombers and VBIEDs** (Captain, 2026-10-11) belong in this wave as insurgent behaviour.
- **AH-1Z, MRAPs, Bradley, Abrams:** fielded by the US and close allies that operate them (UK and
  Canada: MRAPs only).

## Already in the code to build on

| Piece | Where | What it gives wave 6 |
|---|---|---|
| Reputation per faction | `Economy.reputation`, `change_reputation`, `tier()` | Plain numbers, saved with the campaign |
| Tier thresholds | `data/factions.json` `reputation_tiers` (-100/-30/0/30/70), `MissionRegistry.tier_index` | Five tiers already; ids say `wary`, the decided name is Distrusted |
| Rep-gated work | `ContractsGen.generate_board` (fixers' `min_rep`), `max_points` (negotiation points per tier) | The first two unlocks already work by tier |
| Factions | `data/factions.json`: Meridian (employer), Black Ridge (insurgent), Coastal Salvage Union (neutral), Vantage Group (rival PMC, hostile) | All placeholders except Vantage, which has real loadouts and exos |
| Enemy faction per zone | `EnemyResponse.enemy_faction` (set from the live contract's target) | The hook for enemy gear by region |
| Enemy high command | `EnemyCommand` (hot zones): finite reserves, reoccupation, and a commander's `caution` kept per zone across deployments | The seed of the persistent world: per-zone enemy state that outlives a deployment |
| Technicals and vehicle QRFs | `VehicleQrf`, wave 5 vehicles | Insurgent light vehicles and the VBIED's carrier |
| Charges ride people and vehicles | `Charges` | The bomber's vest and the VBIED's load |
| Hunter teams | `EnemyResponse` tier 3+ hunters | The generic bounty hunters' AI, already there |

## Calls for the Captain (proposed answers)

1. **What each tier unlocks.** Proposed:

   | Tier | Contracts | Pay | Shop | Supports | Allied troops |
   |---|---|---|---|---|---|
   | Hostile | none; their hunters come for you | - | - | - | - |
   | Distrusted | public board only | x0.9 | basic | - | - |
   | Neutral | board + first fixer | x1.0 | standard | heli resupply/extraction | - |
   | Trusted | fixers' special jobs, joint ops | x1.15 | their military kit, MRAPs | + transport, AAV | one element per deployment |
   | Allied | their story arc, campaign operations | x1.3 | their best kit, armour | + gunship | two elements per deployment |

2. **Allied troop types.** Proposed: a rifle squad (8, US / UK / Canada by employer, their own kit),
   a weapons team (MG + AT), and at Allied a mounted section in an MRAP. They fight as their own group
   on the AI the squad already has; the player can ask for "move to", "hold" and "assault" through
   the support menu, not command them.
3. **Support-menu limits for allied troops.** Proposed: called from the support budget like the helis
   (cost Proposed), one at a time, a 20-minute cooldown after one is lost or released, none in a
   zone where the squad's employer has no presence.
4. **The faction set that replaces the placeholders.** Proposed: keep Meridian (employer) and Vantage
   (rival PMC); the US, UK and Canada as the allied employers (their own boards, rippling together);
   Black Ridge as the insurgents; one conventional army with Russian / Chinese / Iranian kit by region
   under an original name; the Salvage Union stays neutral. All company and unit names original.
5. **Side lockout length.** Proposed: the current deployment plus 3 campaign days.
6. **Decay.** Proposed: 1 point a campaign day toward Neutral after 5 days without a job; Allied
   floors at Trusted while the squad works for them at least once a week.
7. **Heat.** Proposed: heat per faction 0-100, from kills of their men, sites destroyed and their
   contracts sabotaged; generic hunters from 40, named hunter squads from 80; it cools 2 a day.

## Build order (proposed)

1. **6a Reputation core.** Tier names, ripple (faction alliances in `factions.json`), decay on the
   campaign clock, side lockout on the board, the unlock table driving pay, shop and supports. Mostly
   `Economy`, `ContractsGen`, the board and the shop; tests in the campaign suites.
2. **6b The faction set and enemy gear by region.** Data first: factions, nations, loadouts per
   region, which faction a zone's enemy is.
3. **6c Persistent world and faction simulation.** Per-zone site state (who holds what, damage,
   repairs and reoccupation on the campaign clock, on top of `EnemyCommand`'s memory), the war
   between factions between deployments, and war-driven contracts on the board.
4. **6d Heat and bounty hunters.** Heat per faction, generic hunters into missions near their ground
   (EnemyResponse's hunters), then named Nemesis-style squads that remember the squad.
5. **6e Allied troops.** Joint operations and the support-menu call.
6. **6f Bombers and VBIEDs.** Insurgent behaviour: a hostile wearing a charge closes and sets it off,
   with tells (bulky clothes, ignoring shouts); VBIEDs as technicals or civilian cars with a charge.

6a and 6b can run side by side; 6c needs 6b's faction set; 6d needs 6a's tiers.
