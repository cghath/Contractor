# S1: hostiles wipe the team at the objective (co-op soak), 2026-10-14

**Verdict: soak-bot problem plus a balance item. No clear game bug, so the game code is unchanged.**

## What the logs show

| Run | What really happened |
|---|---|
| S0743 (30 min lossy) | No wipe. 6/6 contracts, 0 bot problems. Every "down" is either the planned knock-out or one hostile hit that was revived. |
| S0755 (play-along, human not in yet) | **Not a wipe.** The host bot was the only player in the zone (the client bots never deployed). The harness picks the host as the knock-out victim with `medic_bot -1` (coop_soak.gd:582-588 on test/coop-soak 33d3e87), so it knocks itself out with nobody left to treat it. After 45 s it logs "every player is down: giving up" (coop_soak.gd:1646). Friendly AI blood stayed at 1.00 throughout. "(regathered failed)" comes after that: Sparrow carries the respawned host's old body, Smokey wanders. |
| S0736 cycle 3 (lossy, Harbour yard) | **The real wipe.** See below. |

S0736 cycle 3, host snapshots (`t` = seconds into the run):

- At 620 s the bots advance in the open at a walk (4 m/s), all four within about 4 m of each other. The squad AI (Boone, Gunny) is 40-60 m behind them.
- From 650 s the checkpoint group (6 insurgents, static, `aim` flag set) fires at 160-200 m: 10, then 62, then 44, then 19 rounds per 10 s.
- The players go down at 112-140 m: Players/1 at 670 s, a second at 675 s, a third at 684 s. Blood is still 0.97-0.99 when they drop, so they were knocked out by hits, not by bleeding out.
- In that window the players fired **0 rounds** and the friendly AI fired **0 rounds** for the whole run. The AI stood behind the players, so `_friendly_in_line` (squad_ai.gd fire discipline) kept them from firing through them. That is the rule working as intended.
- The phase stayed "advance" until 829.6 s, which is the full `ADVANCE_S` of 210 s. Only then did "fight" start, with three of four players already down. No hostile took a hit (6 of 6 up).

## Root cause (soak bots, tests/coop_soak.gd on test/coop-soak)

1. **coop_soak.gd:575.** The advance ends only within 70 m of the objective, or when a hostile is within `HUNT_STOP_M * 2` = 90 m of the host. It does not end when the host is down: `_me()` is never null for a downed player. Hostiles engage from 200 m, so the bots walk through 110 m of fire with `_fight = false`. While `_fight` is false they stand upright, never take a stance and never shoot.
2. **coop_soak.gd:50.** `ENGAGE_M` is 140 m, but the garrison's reach is `SquadAI.SIGHT_RANGE` = 200 m (squad_ai.gd:140). Even in "fight", the bots cannot answer anyone between 140 and 200 m.
3. **coop_soak.gd:582-588.** The knock-out still runs when there is no medic (`medic_bot == -1`), which guarantees "every player is down" for a lone host (S0755).

The proposed patch is `docs/audits/s1_soak_contact.patch`, against test/coop-soak 33d3e87. It is for the owner of test/coop-soak to apply; it was not committed there. It does three things:

- Ends the advance on first contact: this bot is hurt or down, any player is down, or a hostile within `ENGAGE_M` has a clear line to it.
- Raises `ENGAGE_M` to 200 m.
- Skips the knock-out when nobody else is in the zone.

## Game side: checked, no clear bug

- **Spawn on top of the squad:** no. The checkpoint was static, 300+ m from the insertion, which was in dead ground hidden from 100% of the hostiles.
- **Reinforcement timing:** R1/R3 did not take part in the cycle-3 wipe. The fire came from `AI/checkpoint_*`.
- **Aim through cover:** no. The bots were on open ground in line of sight. The bots' own ray check (open air) shows no wall between them.
- **Aim model:** `Soldier.ai_spread_direction` applies `ADS_SPREAD_MULT` (0.12) to the AI's `ai_spread_deg`. This has been the case since 5f71267, the first ADS commit, so it is not a regression. `SquadAI._aim_error_deg` adds `(1 - combat) * 1.2` degrees, plus `suppression * 4`.

## Balance numbers (for the tuning pass already queued: NEXT_SESSION "S1 hostiles very lethal at ~150 m (P0362:94-109)")

The table below is a Monte Carlo of one garrison rifleman. Inputs:

- Garrison combat 0.45 (compound_level.gd:583); Mk18 `ai_spread_deg` 1.4, aiming, standing still.
- Burst hold `lerp(0.35, 0.1, combat)` degrees; aim error 0.66 degrees.
- Target: a standing man, aimed at the chest, silhouette about 0.45 x 1.55 m with the head on top.

| Range | Hit per round, unsuppressed | Hit per round, suppression 0.5 |
|---|---|---|
| 100 m | ~20% | ~2.4% |
| 150 m | ~11% | ~1.0% |
| 200 m | ~6.6% | ~0.6% |

With no fire coming back (suppression 0), 135 rounds at 110-160 m comes to about 13 expected hits on upright walkers. That matches three players down in 15 s. Suppression is what takes away about 90% of that lethality. A team that fires back, as players do and as the patched bots will, is far safer.

**Recommendation (Captain's call, not done here):**

- Keep the aim model.
- If 150 m still feels too lethal once the bots fire back, the smallest lever is a range term in `_aim_error_deg`, for example `+0.25 deg per 100 m past 100 m` for unskilled AI. That would roughly halve the 200 m hit rate and leave close range alone.
- Alternatively, wire the pending doctrine `aim_deg` (insurgent 0.6), which is already proposed in data/doctrines.json.
- First re-measure with the patched soak: down-events per cycle before the "fight" phase should drop to about 0.
