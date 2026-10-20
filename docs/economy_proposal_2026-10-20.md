# Economy balance proposal (2026-10-20)

**Status: Built on claude/economy (2026-10-20): eight of the nine numbers and both loopholes.
Item 2 (`hot_zone_pay_mult` 1.0) was undone the same day, when the Captain dropped the hot zone's
arrival contracts (see "Hot zones start small" at the end). The calls made in building it are
listed in "Built" for the Captain to confirm.** The reasons are in
[economy.md](economy.md). The rest of this document is the proposal as written; its "now"
numbers predate the loot rotation (see "Built" for the rerun).

The Captain's read: too easy overall, but mission expenses swing it negative fast. Both are
true, and they have different causes:

- **Too easy** comes from income, not from missing costs. A careful squad ends five weeks
  with about $1,000,000 (from $135,000 after hiring), a middling squad that takes hot-zone work
  with about $1,400,000. Three things carry it: contract pay that is about twice the running
  costs of the days it takes, **intel that sells for a flat $6,000 a piece** (a quarter of a
  looting squad's income) and **hot zones, whose 3 to 6 arrival contracts each pay their advance
  on arrival and keep it even if nobody does them** ($80,000 a hot deployment, up front).
- **Expenses swing it negative** for two reasons. The real ones are a few shock lines: a lost
  helicopter ($40,000), the rising respawn price ($4,000, then $6,000, $8,000, ...) and the death
  benefit ($15,000 per man), which together make a sloppy squad's worst deployment cost
  $150,000. The other reason is how the money is shown: the weekly bill (about $45,000) lands
  in whichever debrief crosses the week's end, and the debrief's "net after expenses" leaves out
  the loot and intel. So even the careful squad, which makes money on 99% of its deployments,
  sees 1 debrief in 5 come out negative, the worst at -$50,000.

## The headline changes

1. **Contract pay about a third lower**, and hot zones pay by volume rather than by rate
   (`difficulty_pay` and `hot_zone_pay_mult`), and the no-civilian-casualties bonus halved.
2. **Intel sells for what it's worth** (its own `intel_value`, $600 to $3,000), not a flat
   $6,000. That was already the documented intent in `data/prices.json`.
3. **A hot zone's arrival contracts pay on completion**, not on arrival.
4. **Wages and upkeep are charged every day**, a seventh of the week's bill, so each debrief
   carries its own days and no debrief gets the whole week's bill.
5. **The shock costs are capped**: a lost helicopter costs a $15,000 deductible (insured), a
   bought respawn rises by a quarter of the price each time and never costs more than $8,000, and
   the death benefit is $10,000.

What it does, in the sim (five in-game weeks, 40 campaigns per profile, mean cash; the sloppy
squad's proposed $125k is $98k once its loans are paid back):

| Profile | Cash at day 35 now | Proposed | Its worst deployment now | Proposed | Debriefs shown negative now | Proposed |
|---|---|---|---|---|---|---|
| Careful (few losses, loots everything) | $1,011k | $490k | -$17k | -$15k | 18% | 20% |
| Median (some losses, takes hot zones) | $1,436k | $582k | -$60k | -$45k | 22% | 34% |
| Sloppy (heavy losses, many supports) | $766k | $125k | -$150k | -$99k | 45% | 68% |

Careful and median squads still grow every week (about $70k and $90k a week, against $175k and
$260k now), so the big purchases (FOB tiers, the air wing, MRAPs, exos) take a campaign rather
than a fortnight. A sloppy squad now treads water instead of getting rich anyway: it ends near
where it started, leans on emergency loans, and 2 campaigns in 40 ran out of credit. No
competent squad's single deployment cost more than $45,000 in the sim, a third of the starting
cash. The worked example below shows a real disaster.

## How it was measured

`tools/economy_sim.tscn` (new, not a test suite: CI and `tools/run_tests.sh` never run it):

    <voxel godot exe> --headless --path . res://tools/economy_sim.tscn -- --runs 40

It plays short campaigns through the **real** economy code in a throwaway campaign that is never
saved: the contract board as `Contracts` refreshes it each day (`ContractGen`: types, ratings,
pay, fixers, clawback terms, hot zones and their arrival contracts, leads, reputation tiers and
lockouts), negotiation (`ContractGen.deal`), `Contracts.server_accept`, `server_start_deployment`
and `server_end_deployment` (the debrief, `DebriefCalc.compute` and `.expenses`), the weekly bill
and emergency loans (`Economy`), support calls (`Economy.server_pay_support`, budget first),
salvage picks (`DebriefCalc.best_value_picks`, the "claim best value" helper), intel sales
(`Contracts.server_sell_intel`), pallets (`Pallets`), the hiring board and wage growth (`Hiring`,
`Roster.after_mission`), shop prices (`Prices`) and the loot that really spawns: the OPFOR kit
(`CompoundLevel.hostile_loadout`) and each site's loot boxes and HQ strongbox
(`WorldValuables`, same seeds, same contents).

The fighting is replaced by dice: a **play profile** says how often the squad wins, who gets
hurt, how many supports it calls and how much it loots. Those numbers are assumptions (the
table below); the economy's response to them is measured. The proposed rules that need code are
modelled in the sim (each says how), the data changes are applied to the loaded data in memory.

| Assumption | Careful | Median | Sloppy |
|---|---|---|---|
| Takes (briefed rating) | up to 3, contract zones only | up to 4, hot zones too | anything |
| Negotiation (4 points at Neutral) | 2 salvage, 1 support, 1 pay | 1 salvage, 1 support, 2 pay | 2 support, 2 pay |
| Contract won, rating 1 to 5 (hot zone x0.92) | 97% to 75% | 93% to 60% | 85% to 42% |
| AI squadmates killed per deployment | 0.05 + 0.04 x rating | 0.1 + 0.1 x rating | 0.3 + 0.2 x rating |
| Dead man's body (and kit) brought home | 90% | 60% | 30% |
| Wounded / player deaths per deployment (hot x1.3 / x1.5) | 0.8 / 1 | 1.5 / 3 | 2.5 / 6 |
| Supports called (chance each; hot x1.5) | transport, extraction 50% | + resupply 40%, medevac 30% (70% heli) | all, + AAV 30%, allied troops 20% |
| Helicopter shot down, per call | 2% | 5% | 10% |
| Items carried off the dead (dearest first) | 12 | 6 | 2 |
| Loot boxes opened at the target / other sites / finds in the open | all / 1 site / 2 | 70% / none / 1 | 30% / none / none |
| Intel | sells all | sells half | turns it in |
| Pallets and site vehicles | kept as FOB stocks / tags 60% | sold / 30% | left |

Repeat runs agree to about 2% (a few campaigns aren't exactly reproducible from their seed: a
repeat gave the median squad $1,465k now and $592k proposed at day 35, against the tables'
$1,436k and $582k); the careful squad's numbers repeat exactly.

Squad of 6 out (2 players, 4 AI) from a roster of 8, the dead replaced from the hiring board at
once; no gear bought (cash is wealth); deployments back to back. Not modelled: buying gear and
upgrades, vehicle repairs and fuel, the medbay, wounded days off, MIA recovery, rival teams,
heli upgrades (their `lost_mult`), better-kitted factions' loot, and more than one contract per
contract-zone deployment.

## Where the money comes from and goes, now

Mean per deployment, current rules:

| | Careful | Median | Sloppy |
|---|---|---|---|
| Contract pay (advance + completion) | $50.2k | $110.7k | $114.9k |
| Bonuses (optional objectives, no civilians, hazard) | $9.4k | $18.2k | $16.8k |
| Loot sold / salvage / contraband / pallets | $7.4k / $1.4k / $2.6k / $0.5k | $7.8k / $3.5k / $1.0k / $2.8k | $4.5k / $2.9k / $0.2k / - |
| **Intel sold** | **$24.6k** | $8.0k | - |
| Wages / upkeep | -$8.7k / -$7.9k | -$8.9k / -$8.2k | -$8.9k / -$8.4k |
| Field costs | -$9.2k | -$11.9k | -$12.2k |
| Death benefit / treatment / hiring | -$2.2k / -$1.0k / -$0.3k | -$7.1k / -$2.0k / -$0.9k | -$15.5k / -$3.3k / -$1.9k |
| Supports (cash) / **lost helicopters** / **respawns** | - / -$0.6k / - | -$5.8k / -$3.9k / -$1.1k | -$9.1k / **-$13.7k** / **-$15.6k** |
| Economic net (its own days of wages and upkeep) | +$65.5k | +$101.4k | +$49.7k |

Share of a careful squad's income: contract pay 52%, bonuses 10%, **intel 26%**, loot and the rest
12%. Of its costs: wages 28%, upkeep 25%, field costs 30%; the shock lines under 10%.

By zone (current): a median squad's contract-zone deployment nets $34k in 2.6 days; its
**hot-zone deployment nets $286k in 3.6 days**, $80k of it arrival advances kept whatever
happens. A sloppy squad loses $18k a contract-zone deployment on average and makes $179k a
hot-zone one, so it ends rich anyway: the hot zone pays for everything.

Why the shown "net after expenses" misleads: it includes any weekly bill that fell due during
the deployment (often $45,000 at once) and leaves out the loot, salvage and intel sold after it.
Careful squad, current: the shown net averages $30k (18% negative, worst -$50k) while the real
result averages $65k (1% negative, worst -$17k).

## Proposed numbers

| # | Where (file, key) | Now | Proposed | Why | Effect in the sim |
|---|---|---|---|---|---|
| 1 | `data/contracts.json` settings `difficulty_pay` | `[0, 0.5, 0.7, 0.9, 1.15, 1.45]` | `[0, 0.35, 0.5, 0.6, 0.75, 0.95]` | Pay is about twice the running costs of the days it takes. About a third off at every rating keeps the curve's shape (a 5 still pays 2.7x a 1). | Careful squad's contract pay $50k -> $34k a deployment. A standard rated-3 coast raid (1 pay point, 2 days) pays $30,250 against $21,100 of wages, upkeep and field costs: about 30% of its pay left before bonuses and loot, the bottom of the 30-45% economy.md's earlier pass aimed for. |
| 2 | same, `hot_zone_pay_mult` | 1.4 | 1.0 | A hot deployment already hands the squad 3 to 6 contracts at once, each rated higher (more enemies, better ones); it doesn't also need a better rate. Hazard pay (5% a pressure tier) still rewards staying. | Median hot deployment's pay $309k -> $126k; net $286k -> $99k. |
| 3 | `scripts/campaign/contracts.gd` `_hot_zone_extras` (code) | arrival contracts signed on standard terms: 30% advance on arrival, kept if they lapse | an arrival contract pays nothing up front, all of it on completion (it needs a terms exception: `advance_min` is 10%) | Walking into a hot zone and straight out pays $80k. | Sim: the advance is handed back at once and added to the completion pay. |
| 4 | `data/contracts.json` settings `clean_bonus_share` | 0.1 | 0.05 | It pays on almost every contract (it's the norm, not a feat); with the optional objectives' 10-25% the bonuses are 10-12% of all income. | Careful bonuses $9.4k -> $4.7k a deployment (with item 1). |
| 5 | `scripts/campaign/contracts.gd` `server_sell_intel`, `scripts/ui/debrief.gd` (its Sell button), new setting `intel_sale_mult` (code) | flat `intel_sale_price` $6,000 a piece | `intel_value` (data/items.json) x `intel_sale_mult` 1.0: laptop $3,000, ledger $1,800, phone $1,200, documents $800, USB drive $600, Vantage ledger $4,000 | prices.json already says intel "is worth its intel_value"; $6,000 for a USB drive worth $600 made intel a quarter of a looting squad's income. Data-only fallback if code waits: `intel_sale_price` 6000 -> 1500. | Careful intel $24.6k -> $4.5k a deployment. |
| 6 | `scripts/campaign/economy.gd` `advance_days` / `pay_week` (code) | wages + upkeep (+ loan installments) once a week | wages and upkeep every day, a seventh of the week's bill (loan installments stay weekly) | Each debrief then shows its own days' running costs; no single debrief takes a $45k week. The weekly total is unchanged. | Sim: a "week" of one day, upkeep $3,000 a day, loans over the same 8 weeks. Careful worst shown debrief -$50k -> -$29k. |
| 7 | `data/prices.json` `lost_supports` (all five) | resupply 30,000; transport, extraction, medevac, cargo 40,000 | 15,000 each (an insurance deductible; the Petrel x1.3 = $19,500, the Razorback x1.8 = $27,000) | A shot-down helicopter is the biggest single line a competent squad can't avoid. | Median lost-heli cost $3.9k -> $1.4k a deployment; sloppy $13.7k -> $5.2k. |
| 8 | `data/prices.json` `respawn_rise`; new key `respawn_max` (code: `RosterDeployment.respawn_cost` caps at it) | rise 0.5 (4,000, 6,000, 8,000, 10,000...), no cap | rise 0.25 (4,000, 5,000, 6,000, 7,000), `respawn_max` 8,000 | The rising price is the steepest curve in the game: a bad hot zone ran up $127,000 in respawns. The free pool (4, hot 8) and the first price stay. | Sloppy respawns $15.6k -> $11.2k a deployment. The biggest respawn bill in one deployment: $57k with the cap; $127k in a trial run with the 0.25 rise but no cap. |
| 9 | `data/prices.json` `operations.kia_benefit` | 15,000 | 10,000 | In step with pay a third lower; losing a man still costs the benefit, a sign-on fee (~$2,100) and his experience. | Sloppy death benefits $15.5k -> $10.6k a deployment. |

Deliberately unchanged: wages (`Roster.WAGE_*`), `weekly_upkeep`, field costs
(`operations.per_head_day`), shop prices and `sell_ratio`, support call prices, the support
budget (`support_per_point` $23,000, Noah's call: one point covers an infil and exfil; see the
observations), start cash, loans, fixers, reputation tiers.

## Before and after, by profile

Cash by day (mean, with the 10th and 90th percentile), 40 campaigns each:

| Day | Careful now | Careful proposed | Median now | Median proposed | Sloppy now | Sloppy proposed |
|---|---|---|---|---|---|---|
| 0 | $135k | $135k | $135k | $135k | $135k | $135k |
| 7 | $332k (263-399) | $210k (173-242) | $457k (206-802) | $242k (145-374) | $283k (47-559) | $109k (-8-224) |
| 14 | $491k (414-593) | $274k (230-323) | $669k (321-941) | $316k (184-430) | $368k (18-765) | $98k (-5-204) |
| 21 | $649k (559-791) | $342k (281-402) | $911k (490-1291) | $407k (222-571) | $503k (191-944) | $120k (10-335) |
| 28 | $833k (691-1023) | $413k (348-494) | $1151k (650-1617) | $486k (304-685) | $635k (223-1108) | $128k (-10-298) |
| 35 | $1011k (866-1217) | $490k (411-586) | $1436k (827-2025) | $582k (354-784) | $766k (253-1292) | $125k (-15-333) |

Per deployment:

| | Careful now | Careful proposed | Median now | Median proposed | Sloppy now | Sloppy proposed |
|---|---|---|---|---|---|---|
| Economic net, mean | $65.5k | $26.5k | $101.4k | $34.5k | $49.7k | -$2.7k |
| 10th percentile | $34.3k | $10.0k | -$6.3k | -$12.7k | -$65.9k | -$58.2k |
| Worst | -$16.8k | -$15.1k | -$59.7k | -$45.3k | -$149.5k | -$99.2k |
| Share negative | 1% | 4% | 14% | 21% | 45% | 63% |
| Contract zones, net mean | $65.5k | $26.5k | $33.9k | $12.2k | -$18.3k | -$20.1k |
| Hot zones, net mean | - | - | $285.5k | $98.9k | $178.9k | $30.7k |
| Debrief "net" as shown, mean (share negative) | $29.9k (18%) | $10.5k (20%) | $79.9k (22%) | $18.8k (34%) | $44.4k (45%) | -$9.0k (68%) |

Income shares, proposed: careful contract pay 62%, bonuses 9%, loot 13%, intel 8%, the rest 8%;
median contract pay 70%, loot and salvage 14%, pallets 3%, intel 2%.

The shown debrief net is still negative more often under the proposal, because pay is lower and
the debrief still can't count the loot sold after it. With daily billing it's now an honest
"what the contract made after its own days", so an optional small UI change: label it "Net after
expenses (before loot, salvage and intel)", or add a closing line with what was sold.

## A disaster, worked through

A careful squad's bad day: a rated-3 raid on the coast (2 days), 1 pay point, 1 support point
(transport and extraction from the budget), and it all goes wrong: failed, 2 AI killed, 2
wounded, the transport shot down, a resupply called from cash, 6 player deaths (2 bought).

| | Now | Proposed |
|---|---|---|
| Advance (kept: failed, not voided) | +$13,700 | +$9,100 |
| Death benefits (2) | -$30,000 | -$20,000 |
| Lost helicopter | -$40,000 | -$15,000 |
| Respawns bought (2) | -$10,000 | -$9,000 |
| Resupply call, treatment (2), field costs (6 x 2 days) | -$22,800 | -$22,800 |
| Wages and upkeep, 2 days; two replacements hired | -$16,900 | -$16,900 |
| **Net** | **-$106,000** | **-$74,600** |

The shock lines (deaths, helicopter, respawns) fall from $80,000 to $44,000. Against the $135,000
the company has after hiring, it survives either way, but now with room to spare; the emergency
loan (`safety_floor_cash`) is still there. Measured against what a good mission earns it still
hurts: about three of its average deployments (loot included) to earn back, where today it's
about one and a half, because the good missions pay less too. That is the tighter progression.

## Hot zones: how sure is this

The hot-zone result leans most on the assumptions: the sim lets a squad finish each of a hot
zone's 3 to 6 contracts with nearly its usual odds. A sensitivity run with at most 2 contracts
done per hot deployment and a lower win chance (x0.75):

| (sim `--hot_cap 2 --hot_win 0.75`) | Median now | Median proposed | Sloppy now | Sloppy proposed |
|---|---|---|---|---|
| Cash at day 35 | $1,055k | $384k | $485k | $30k |
| Hot deployment, net mean | $183k ($76k of it arrival advances) | $46k | $115k ($77k) | $3k |
| Contract-zone deployment, net mean | $32k | $9.7k | -$21k | -$21k |
| Out of credit by day 35 | 0 of 40 | 0 of 40 | 0 of 40 | 4 of 40 |

Either way a hot zone stays the best money per day for a squad that can handle it (about 3 to 6
times a contract zone's, before its risk) and stops paying a sloppy squad for turning up. The
main runs' numbers above are the generous end.

If playtests show hot deployments routinely finish 3 or more contracts in their 2 days, a
further option (code, not modelled): a hot deployment takes a campaign day more for each
contract done after the first, so the wages and upkeep follow the work.

## Loopholes seen in the code (not in the sim)

- **Intel can be sold twice** (looks possible; check in play). Selling it to a faction
  (`server_sell_intel`) or turning it in doesn't take the item away; carried home, it can go
  into the stash and the shop buys it again at 40% of its price (`Prices.sell_price` doesn't
  refuse intel; the base shop UI lists it). Fix: the shop won't buy intel, or a piece sold or
  turned in leaves the stash.
- **Hire and release for kit.** A new hire brings their role's kit free (`Hiring.hire`), and
  letting someone go puts their gear in the stash (`BaseHub.server_release`). A kit is worth
  $6,100 to $11,600 at shop prices and sells for $2,500 to $4,600; the sign-on fee is about
  $2,100 (median; $1,800 to $2,500). So hiring and releasing at once nets $400 to $2,500 cash,
  or a medic's kit for a fifth of its price, six candidates every three days. Fix: someone let
  go keeps the kit they were issued (only what the company added comes back), or the fee
  includes the kit.

## Observations, no change proposed

- **The support budget is the best use of a negotiation point.** One support point is $23,000
  of supports; one pay point is 10% of the pay (about $3,000-6,000 under the proposal). A squad
  that calls helicopters should never take pay points. That's Noah's recent call (2cf1026: one
  point covers an infil and exfil), so it stays; the Captain may want it nearer one call
  ($12,000) once pay is lower.
- The contract-zone safe job (`safe_pay_mult` 0.7 on a rating-1 job) already pays less than the
  days it takes cost; it only pays with loot. Under the proposal more so (a rated-1 raid pays
  $11,000 against about $21,000 of wages, upkeep and field costs for its 2 days; $16,000 today). It stays a
  safety floor because it can't fail badly, not because it earns.
- Contraband to Mama Rook (100% of its price) and loot sold at the shop (40%) look about right:
  together 10-15% of a looting squad's income.

## When it goes in

Tests that read the numbers being changed (they need updating with the change):
`tests/contracts_test.gd` "Economy balance" (two weekly bills in 14 days: daily billing makes
14) and the intel sale check (`cash + 6000`), `tests/base_test.gd` "Wages" (the week's bill paid
on its day). The "Economy balance" profit checks use a fixed deal and keep passing. The sim's
`PROPOSED` table in `tools/economy_sim.gd` holds these numbers; rerun it after any change.

## Built (claude/economy, 2026-10-20)

Every number in "Proposed numbers" is in `data/` as proposed, and every rule is in the code:
daily wages and upkeep (`Economy.pay_day`), intel by its value (`Prices.intel_sale_value`),
arrival contracts paid on completion (`Contracts.server_accept`), the respawn cap
(`respawn_max`, `RosterDeployment.respawn_cost`). Both loopholes are closed (see
[economy.md](economy.md), "Loopholes closed"). The sim no longer models any of it: its
`PROPOSED` table is empty, ready for the next round.

### Measured again

The loot rotation (about 72 items, rarity-tiered loot tables) landed after this proposal was
measured, so the "now" side was rerun: the sim's loot mirror was moved to the new
`WorldValuables.site_plan` / `pool_roll` (it no longer parsed), then run on a72ca02 (the commit
before the overhaul) and on claude/economy with the same seeds. 40 campaigns, 35 days each.

Cash by day (mean, with the 10th and 90th percentile):

| Day | Careful before | Careful built | Median before | Median built | Sloppy before | Sloppy built |
|---|---|---|---|---|---|---|
| 0 | $135k | $135k | $135k | $135k | $135k | $135k |
| 7 | $265k (208-329) | $184k (147-218) | $462k (174-900) | $238k (127-399) | $289k (29-571) | $115k (9-211) |
| 14 | $383k (317-468) | $235k (183-277) | $712k (281-1091) | $315k (145-482) | $409k (17-962) | $92k (-12-220) |
| 21 | $510k (381-631) | $288k (225-359) | $976k (480-1437) | $408k (162-622) | $516k (114-951) | $86k (-19-238) |
| 28 | $623k (491-763) | $338k (269-417) | $1265k (689-1833) | $499k (229-728) | $610k (52-1313) | $105k (-17-316) |
| 35 | $752k (598-884) | $395k (314-490) | $1538k (824-2265) | $609k (296-923) | $701k (143-1430) | $113k (-58-343) |

Per deployment:

| | Careful before | Careful built | Median before | Median built | Sloppy before | Sloppy built |
|---|---|---|---|---|---|---|
| Economic net, mean | $46.3k | $19.8k | $111.4k | $37.4k | $44.8k | -$5.0k |
| 10th percentile | $16.0k | $1.6k | -$2.8k | -$12.6k | -$72.4k | -$60.4k |
| Worst | -$36.3k | -$28.2k | -$78.1k | -$49.6k | -$161.8k | -$116.5k |
| Share negative | 3% | 8% | 12% | 19% | 48% | 62% |
| Contract zones, net mean | $46.3k | $19.8k | $38.2k | $13.9k | -$24.5k | -$24.5k |
| Hot zones, net mean (arrival advances in it) | - | - | $276.6k ($80.3k) | $94.6k ($0) | $166.3k ($77.6k) | $31.1k ($0) |
| Debrief "net" as shown: mean, worst (share negative) | $25.5k, -$84.1k (20%) | $7.9k, -$39.6k (23%) | $92.3k, -$83.6k (21%) | $22.7k, -$60.3k (29%) | $39.9k, -$182.1k (48%) | -$11.3k, -$131.0k (66%) |
| Out of credit by day 35 | 0 of 40 | 0 of 40 | 0 of 40 | 0 of 40 | 1 of 40 | 7 of 40 |

Intel was 15% of a careful squad's income before ($156k a campaign) and is 5% built ($31k).
A careful squad still grows about $52k a week and a median one about $95k (against $123k and $281k before); a sloppy one treads
water near its start and leans on loans. The worst debrief a careful squad sees falls from
-$84k to -$40k (no week's bill at once, the deductible and the cap), which is the "swings
negative fast" half. The built run matches the proposal's modelled run (rerun on the same
loot) to within 2% at day 35: careful $395k against $394k, median $609k against $595k, sloppy
$113k against $115k.

The share of debriefs shown negative rises (careful 20% to 23%), as the proposal expected: pay
is lower, and the shown net is now the contract's own result before loot. The debrief now says
so ("Net (before loot)", plus where the money came from and "Sold here").

### Calls made in building it (for the Captain to confirm)

1. **Radio contracts pay on completion too**, not only the arrival contracts: "Radio for a
   contract" could be pressed again and again, each paying a 30% advance kept if it lapsed.
2. **Intel: both fixes, and two more.** The shop never buys intel, and intel brought out never
   goes to the stash (it's handed over in the debrief). A piece with an id already debriefed is
   worth nothing if carried out again. Intel still stowed on the squad at extraction is banked
   then, so it can't go home in a pack. Intel left in the field isn't salvage.
3. **Hire and release: they keep the kit they were issued** (not "the fee includes the kit").
   Issued kit not on them comes out of the stash. If it isn't there, its shop sell value is
   charged, for durable kit only: ammo, magazines, medical, grenades and AT4s are used up.
4. **The HVT hard case is worth $3,000 as intel** (a laptop's worth). It had no value of its
   own and sold at the flat $6,000.
5. **A deployment's debrief shows only its own days' wages and upkeep.** Days waited at base
   are on the ledger and the new Books tab, not in the next debrief.
6. **Not done:** the hot zone's extra campaign day per extra contract (the proposal's option for
   playtests), and the support budget stays at $23,000 a point.

## Hot zones start small (Captain, same day)

> "not all contracts should be active upon entering a hot zone anymore as we have the village
> systems" / "with radios and villages entering hotzones with one or two objs will be good"

Built: a hot zone goes in on the contracts taken for it. The top-up to 3-6 on arrival
(`Contracts._hot_zone_extras`, `HotZoneOps.live_target`, `LIVE_RANGE`) is gone. More contracts
come in over the radio: HotZoneOps' follow-ups as sites fall and contracts are done (at most 4
a deployment), and "Radio for a contract". Both pay nothing up front. Proposed item 3 (arrival
contracts paid on completion) has nothing left to apply to.

The sim now models the radio follow-ups (`Contracts.server_contract_on_spot`; a new profile
assumption "radio": median 0.6, sloppy 0.5 per contract done) in place of the arrival
contracts. That changed the hot zone a lot. Proposed item 2 assumed a hot deployment brings 3-6
contracts; without them, x1.0 left too little:

| Median squad (sloppy) | Hot zone x1.0, arrivals (as built first) | x1.0, no arrivals | **x1.4, no arrivals (built)** |
|---|---|---|---|
| Hot deployment, net mean | $94.6k ($31.1k) | $10.5k (-$27.5k) | **$39.7k (-$15.7k)** |
| Cash at day 35 | $609k ($113k) | $230k (-$32k) | **$364k (-$18k)** |
| Economic net per deployment, mean (share negative) | $37.4k, 19% (-$5.0k, 62%) | $7.2k, 37% (-$21.4k, 76%) | **$18.2k, 32% (-$19.5k, 73%)** |
| Out of credit by day 35 | 0 (7) of 40 | 0 (18) of 40 | **0 (14) of 40** |

So `hot_zone_pay_mult` stays at 1.4. A median squad now grows about $46k a week, a careful one
(contract zones only, unchanged) about $52k. Before the overhaul they grew $281k and $123k. A
sloppy squad sinks rather than treading water. The radio follow-ups taken averaged 0.8 per
median hot deployment. The villagers' jobs aren't in the sim: asking villagers puts a locals'
job on the base board for a later deployment, not into the live one.

Calls for the Captain:

7. **Hot zone pay x1.4 kept** (not the proposed x1.0), because the arrival contracts are gone.
8. **Sloppy squads now go broke** in about a third of the sim's campaigns (14 of 40). If that's
   too harsh, the lever is the shock costs or the emergency loans, not pay.
