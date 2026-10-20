# Hot zones: what's built, the knobs, what's left

Captain, 2026-10-15: "flesh out HZs too, remember multiple missions per and our design". The
design is in [contractor_design_doc.md](contractor_design_doc.md) ("Missions: contract zones
and hot zones (decided)") and [mission_brainstorm.md](mission_brainstorm.md). Most of the hot
zone was built in 4B part 3 ([wave4b_handoff.md](wave4b_handoff.md)); this pass adds the
"several missions per deployment" side. All numbers are Proposed.

## Built

| Design point | Where | State |
|---|---|---|
| Layout: HQ, comms, 1-2 QRF bases, 3-6 outposts, checkpoints, patrol routes, villages, a town | `ZoneDef.generate_hot` | built (4B) |
| Several contracts from one faction live at once, any order | `Contracts.server_start_deployment`, radio follow-ups | **changed (Captain, 2026-10-20)**: the squad goes in on the one or two contracts it took for the zone; more come in over the radio as it works (below), when it radios for one, or from a villager asked there (the locals' job joins the deployment live, once a zone a day: `RebelSupport.server_ask_in`, `Contracts.server_contract_on_spot`). The top-up to 3-6 on arrival is gone. Contracts taken on the spot pay nothing up front, all on completion (economy overhaul) |
| New contracts over the radio, reacting to what the squad did | `HotZoneOps` (`FOLLOW_UPS`) | **new**: a QRF base, outpost, checkpoint or HQ taken out, the comms mast down, or a contract done queues a follow-up at the nearest standing site no other contract holds ("You hit their QRF. Nobody's coming to help the HQ now: hit it."). Needs a field radio; waits without one |
| Resupply and banking mid-zone | supports, `server_items_banked` | built |
| Ends at extraction; unfinished contracts lapse with a rep hit | `DebriefCalc` ("lapsed", `rep_lapse` -3) | built; tested end to end now |
| QRF base destroyed stops its waves | `EnemyResponse._launch_qrf` | built (4B) |
| Comms destroyed slows the response | `Alert.COMMS_DOWN_MULT` (reports 3x slower), `Pressure.COMMS_DOWN_GAIN` | built (4B) |
| Killed officers: less coordination | `EnemyResponse.coordination()` | hunters (4B); **new**: patrols too, only that share of "go and look" orders goes out |
| Alert: calm, raised by noise/sightings/losses, eases when quiet | `Alert` | built (4B): engaged to alerted after 20 min, alerted to suspicious after 90 |
| Alert drives patrols, checkpoints, QRF standby | `EnemyResponse` | built (4B): alerted doubles patrols, closes checkpoints, QRF on standby; reopen as it eases |
| No meter: radio chatter from a looted enemy radio, until they switch frequency | `RadioChatter` | built (4B); **new**: patrol "go and look" orders and checkpoints closing/opening are heard |
| Pressure rises the longer the squad stays: bigger QRFs, armor, hunters | `Pressure`, `EnemyResponse`, `VehicleQrf` | built (4B, V4 technicals); **new**: a time floor quiet can't wear down (tier 1 after ~2 h, tier 2 after ~4 h) |
| Staying pays more | `HotZoneOps.hazard_share`, `DebriefCalc` | **new**: each contract done pays 5% of its pay per pressure tier reached |

## Knobs

Each can be set in `data/contracts.json` "settings" under the lower-case name; otherwise the
constant in `scripts/campaign/hot_zone_ops.gd` holds.

- `follow_up_delay_s` 90, `follow_up_gap_s` 120, `max_follow_ups` 4: radio follow-ups.
- `hazard_pay_per_tier` 0.05: hazard pay per pressure tier.
- `FOLLOW_UPS` (code): what sets a follow-up off, the sites it goes to, the contract types it
  prefers and the employer's line. Types not listed (the mission-variety types) are used when
  none of the listed ones plays at the site, so new types plug in by themselves.
- `Pressure.STAY_FLOOR` 2.5 per `STAY_FLOOR_S` 1800: the time floor.
- `EnemyResponse.coordination()` (`OFFICER_LOSS` 0.2): share of patrol looks ordered.

Tests: `missions` "Hot zone: several contracts, radio follow-ups, alert, staying";
`contracts` hazard pay and the live target. `HotZoneOps.enabled = false` turns the top-up and
follow-ups off for tests that play one contract at a time in a hot zone.

## Left from the design

- Board UI: hot-zone offers still come up singly on the board; there is no "hot zone package"
  view, and the arrival top-up has no accept/decline screen (they're signed on arrival).
- Follow-ups are offered and taken at once; no in-field accept/decline over the radio.
- Contracts carry no "reacting to" link in the debrief (the radio line names it only).
- Mortars, armed helicopters and drones at high alert, and the jammer; LRRP missions.
- Named Nemesis-style hunters (wave 6); rival contractor teams in the zone.
- An intercepted radio doesn't yet hear QRF base readiness or hunter moves (only reports,
  stand-to, QRF waves, patrol looks and checkpoints).
