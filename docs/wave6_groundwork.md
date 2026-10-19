# Wave 6 groundwork: factions

**Status (2026-10-18):** 6a built (tiers with pay by tier, Hostile offers no work, ripple, decay,
side lockout: `Economy`, `Contracts`, `factions.json` "reputation_rules"). 6b started: enemy kits as
data (`Kits`, `factions.json` "kits"), a placeholder regional army ("Federal Army", Eastern-bloc
kit, woodland), contracts against any kitted faction switch the zone's patrols, hunters, QRF waves
(which stayed Black Ridge's before) and, for data kits, garrisons; Black Ridge carries a captured
M4 (Captain: factions known to field AR-pattern rifles use them). Still open in 6b: regional weapon art (Chinese, Iranian), a garrison already spawned before its
contract went live keeps the militia kit. **6c built on today's placeholder faction set** (Captain,
2026-10-18: build an MVP now rather than wait on call 4): `WorldSites` (new, `scripts/campaign/
world_sites.gd`) tracks each hot zone's holder and how firm its grip is (0..1) across deployments
(campaign section "world_sites", the same pattern as `EnemyCommand`'s own per-zone "caution"). A
completed contract against the holder knocks its grip down (`server_contract_won`, hooked from
`Contracts.server_end_deployment`); `Economy.advance_days` ticks it daily (`server_advance_days`):
grip repairs on its own (reoccupation), but at or below `CONTESTED_GRIP` one of the holder's own
`factions.json` "enemies" can take it over instead (the faction war - today that means Black Ridge
and the Federal Army trading `pass_hot`/`ridge_hot`/`city_hot`), flagging a "flashpoint".
`Contracts.server_refresh_board` posts a flashpoint's own war-driven offer (against the new
holder, `ctx.target` forced, `"war_driven": true` on the result) the same way it always posts a
safe job, then clears the flag; every other contract still picks its target the old way (a
first attempt at weighting every hot-zone contract toward the tracked holder shifted
`ContractGen.generate`'s RNG sequence enough to break missions_test.gd's seeded hot-zone/
HotZoneOps checks, so that's out of this slice - only an explicit ctx.target names one). Not
done: no UI shows a zone's holder or
grip yet (debug-only via `WorldSites.holder`/`grip`); 6b's real faction set replacing the
placeholder should just work once it lands, since this reads `MissionRegistry.enemies()`/
`enemies_of()` live. **6e built too** (Captain, 2026-10-18: an MVP now, same call as 6c):
`AlliedTroops` (new, `scripts/supports/allied_troops.gd`) - a friendly 8-man element through the
support menu's "Allied troops" entry, its own `Squad` instance (not the player's), move/hold/
assault orders only (`Squad.give_order`/`order_assault` reused), paid like the helis, a 20-minute
cooldown, gated to Trusted standing with at least one deployment employer. This needed
`Squad.members()` scoped to `SquadAI.squad == self` (it only filtered by faction before, which
never mattered until a second friendly squad existed); fixed, matching `brains()`'s own scoping.
**6e second slice (2026-10-18, Captain: "high command system for the host/1st player to be able to
order these squads to do general things, and map orders", plus the Allied-tier second element and
the weapons team):** up to two elements out at once by the best standing with a deployment employer
(Trusted one, Allied two), each slot with its own 20-minute cooldown; a rifle squad (8) or a weapons
team (4: M240B, ammo bearer, two AT4s; the allied kits' `"mixes"`), in the kit of the employer that
lends it (Meridian, a company, lends US kit). The high command is the host player's alone: the
support menu's Allied troops entry gives general orders to every element (move, hold, assault, flank,
follow me, fall back, release all), and the map's right-click menu has a submenu per element (and
one for all) with map orders at the clicked spot (move, defend, assault, flank, fall back, hold,
release). Every peer's map draws the elements, labels them with their order and size, and dashes a
line to where they were sent (`AlliedTroops.shown`, sent by the host). The contract board shows
each hot zone's holder and grip (firm / holding / contested, and a flashpoint's war job:
`WorldSites.rows()`, carried to clients in Economy's sync). Not done: the MRAP-mounted section.
Groundwork below as written. Wave 6 is next
once the Oct 18 open items are in (Captain, 2026-10-18). This page collects what's already decided, what the code already
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
   **Decided (Captain, 2026-10-18): as proposed; the army is the Eastern Concord Forces.** Built:
   `factions.json` `eastern_concord` (was the `federal_army` placeholder; `MissionRegistry.
   RENAMED_FACTIONS` resolves the old id and `Campaign.load_campaign` moves an old save's standing,
   heat, nemeses and held zones over), its kit by region (`regional_kits`: inland `concord_ru`,
   coast `concord_ir`; `zone_kits`: the Old Quarter `concord_cn`; `Kits.kit_of(faction, zone)`, the
   zone being played by default) with its men named from the kit's nation (`Names.faction_nation`);
   `us_forces`, `uk_forces`, `ca_forces` as employers (allies of each other, so standing ripples
   between them), each with an allied kit (`allied_us`/`allied_uk`/`allied_ca`: M4, L85A2, C8) that
   dresses the allied troops they lend. "Their own boards" is their own contracts on the one board
   (the employer is on every offer); a board per employer is not built.
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
