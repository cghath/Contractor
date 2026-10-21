# Economy balance

Two passes so far. Every number is Proposed (the Captain tunes them).

1. **feat/economy-balance** (Captain: "not enough expenses to balance, so it's easy to stack
   cash"): running costs, field costs, death benefits, lost helicopters, dearer respawns.
2. **The economy overhaul, 2026-10-20** (claude/economy; Captain, 2026-10-16: "too easy overall
   but mission expenses swing it negative fast"): the reasons, the sim and the before/after are in
   [economy_proposal_2026-10-20.md](economy_proposal_2026-10-20.md). Income comes down, the
   shock costs are capped, and the debrief and the base say where the money went.

## The overhaul, 2026-10-20

| What | Was | Now | Why |
|---|---|---|---|
| Contract pay by rating (`difficulty_pay`) | 0.5, 0.7, 0.9, 1.15, 1.45 | 0.35, 0.5, 0.6, 0.75, 0.95 | Pay was about twice the running costs of the days a contract takes. |
| Hot zone pay rate (`hot_zone_pay_mult`) | x1.4 | x1.4 (unchanged) | Proposed x1.0 because a hot zone handed out 3-6 contracts; with the arrival top-up gone (same day), x1.0 left a median squad's hot deployment netting about $10k. |
| A hot zone's arrival contracts | 3-6 handed out on arrival, 30% advance each, kept if they lapse | none: the squad goes in on the one or two it took (Captain, 2026-10-20); more come over the radio and from villagers asked there | Walking in and straight out kept about $80,000; the radio and the villages bring the work now. |
| Contracts taken on the spot (the radio's) | 30% advance up front, kept if they lapse | nothing up front, all on completion | Radioing for contract after contract kept 30% of each. |
| No-civilian-casualties bonus (`clean_bonus_share`) | 10% | 5% | It pays on almost every contract. |
| Intel sold to a faction | a flat $6,000 a piece (`intel_sale_price`) | its own `intel_value` x `intel_sale_mult` 1.0 ($500-4,000; the HVT case $3,000) | $6,000 for a $600 USB drive made intel a quarter of a looting squad's income. |
| Wages and upkeep | once a week | every day, a 7th of the week's | Each debrief carries its own days; none takes a $45,000 week at once. Loan installments stay weekly. |
| Helicopter lost on a support call (`lost_supports`) | $30,000-40,000 | $15,000 (an insurance deductible; air wing types scale it) | The biggest single line a good squad can't avoid. |
| Bought respawns (`respawn_rise`, new `respawn_max`) | +50% each, no cap | +25% each, never over $8,000 | A bad hot zone ran up $127,000 of respawns. |
| Death benefit (`operations.kia_benefit`) | $15,000 | $10,000 | In step with pay a third lower. |

Unchanged on purpose: wages (`Roster.WAGE_*`), `weekly_upkeep`, field costs, shop prices and
`sell_ratio`, support call prices, the support budget (`support_per_point`), start cash, loans,
fixers, reputation tiers.

### Loopholes closed

- **Intel sold twice.** Intel brought out goes to the debrief and never to the company stash
  (`Contracts.without_intel`); the base shop never buys intel (`Prices.sell_price` is 0 for it);
  a piece already debriefed (same `intel_id`) is worth nothing in a later debrief
  (`Contracts._drop_debriefed_intel`, "intel_repeats"); intel still stowed on the people at
  extraction is banked there like at an extraction point (`BaseHub.end_deployment`), so it
  doesn't go home in a pack; intel left in the field isn't salvage.
- **Hire and release for kit.** A hire's role kit is noted as theirs ("issued"); someone let go
  takes it with them, and only what the company added stays (`Hiring.release_split`). Issued kit
  not on them comes out of the stash, or what the shop would pay for it is charged (durable kit
  only: ammo, magazines, medical, throwables and disposable launchers are used up in the field).
- **Advance farming in hot zones** (see the table: no arrival contracts; radio contracts pay on completion).

### Where the money shows

- **Debrief**: header stats Expenses, "Net (before loot)" (the contract's own result; loot and
  salvage sell later) and "Sold here" (intel, pallets sold in the debrief); a "WHERE THE MONEY CAME
  FROM" section (advances, completion pay, bonuses, fines, clawbacks, intel and pallets sold:
  `DebriefCalc.money_in`) and "WHERE THE MONEY WENT" (wages and upkeep with their days, loan
  installments, supports, respawns, lost helicopters, field costs, death benefits, treatment),
  ending with the running costs a day.
- **Base screen**: the header shows funds, costs a day (wages, upkeep) and loans owed; a new
  **Books** tab has the running costs a day, loans and the next installment, the last 7 days of
  money summed by kind (`Economy.ledger_summary`, `Economy.ledger_kind`) and the 20 newest
  payments.
- **Contract board**: costs a day instead of "bill in N days".

## Money flow, typical contract (first pass, feat/economy-balance)

Rated-3 raid, contract zone, squad of 6 out, 8 on the roster. The overhaul's numbers for the same
raid are in the proposal ($30,250 pay against $21,100 of wages, upkeep and field costs).

| | Before | After |
|---|---|---|
| Contract pay (46k base x difficulty 3, ~0.95 term) | ~$48,000 (+10% clean bonus) | ~$39,000 (+10%) (difficulty_pay 1.1 -> 0.9) |
| Days (1 + travel) | 2 | 2 |
| Wages (8 roster, per day) | ~$0.8k (WAGE_BASE 40) | ~$3.5k (WAGE_BASE 300, 150/skill, 6/mission) |
| Base upkeep (per week) | $4,000 | $21,000 |
| Field costs (ammo/meds/fuel/comms) | none | $700 per person per day = $8,400 |
| Death benefit per KIA | none | $15,000 (overhaul: $10,000) |
| Treatment per wounded | none | $1,200 |
| Resupply / transport / AAV / extraction call | 8k / 6k / 12k / 10k | 12k / 9k / 18k / 14k |
| Helicopter lost on an op | free (support gone) | $30-40k replacement (overhaul: $15,000) |
| Respawn past the free pool (4 contract, 8 hot) | 1,000 (+50% each) | 4,000 (+50% each; overhaul: +25%, max 8,000) |

## Where each cost lives

- Wages + upkeep: `Economy.daily_bill()` / `pay_day()`, every day (`advance_days`), listed as
  "Wages (N days)" and "Base upkeep (N days)" in the debrief; a deployment's debrief lists only its
  own days (`Economy.drop_run_bills` when it starts). Loan installments: `pay_week()`, every
  `week_days`. Both through `_pay_bill` (an emergency loan when the cash won't cover it) and the
  `bill_paid` signal. `weekly_bill()` is the week's total (the host's, synced to clients).
- Field costs, treatment: `DebriefCalc.expenses()`, charged in `Contracts.server_end_deployment`.
- Death benefit (feat/fallen): in a campaign, `BaseHub.server_pay_death_benefit`, once per man when his
  death is confirmed (his dog tags or body came out at extraction: `Economy.charge_run`, so the debrief
  lists it as its own line; or he's declared dead `Fallen.DECLARE_DAYS` after he fell, or written off).
  `DebriefCalc.expenses()` counts the dead itself only for a report without the roster (`benefits_paid`).
- Respawns (`BaseHub.server_count_respawn`, `RosterDeployment.respawn_cost` with the cap), support
  calls (`Economy.server_pay_support`), lost helicopters (`HeliSupports.server_lost`):
  `Economy.charge_run` / `note_run_expense`; refunds are listed as negatives.
- Intel sales: `Contracts.server_sell_intel` at `Prices.intel_sale_value`.
- Existing and unchanged: shop prices (gear lost in the field is bought again), repairs, motor-pool
  vehicle repair + fuel, medbay, hiring fee (days of the wage asked), loans.

## Knobs

- `data/prices.json`: `weekly_upkeep`, `default_wage_bill`, `operations.{per_head_day,kia_benefit,wounded_care}`, `supports`, `lost_supports`, `respawn`, `respawn_rise`, `respawn_max`; intel items' prices equal their `intel_value` (data/items.json).
- `scripts/campaign/roster.gd`: `WAGE_BASE`, `WAGE_PER_SKILL`, `WAGE_PER_MISSION`.
- `data/contracts.json` settings: `difficulty_pay`, `hot_zone_pay_mult`, `clean_bonus_share`, `intel_sale_mult`, `support_per_point`.
- The sim: `tools/economy_sim.tscn` (not a test suite; see the proposal's "How it was measured").
  Put candidate numbers in `PROPOSED` in `tools/economy_sim.gd` and run `--variant both`.
- Tests: `tests/contracts_test.gd` "Economy overhaul numbers", "Economy balance", "Weekly wages
  and the safety floor" (daily bills), "Intel, leads and salvage picks"; `tests/base_test.gd`
  "Wages", "Letting someone go", "Respawn pool"; `tests/missions_test.gd` "Radio contracts".

## The same proposal, built twice (2026-10-20)

cghath built the approved proposal on feat/economy-balance (PR #14) while claude/economy built it
here. The Captain chose claude/economy (2026-10-20, "Ours (in v0.5.0)"), so PR #14 is superseded.
The two agree on every number except:
- hot-zone pay: x1.4 here (hot zones start on the contracts taken, by the Captain's call; x1.0
  left too little without the arrival contracts), x1.0 there (3-6 arrival contracts);
- the HVT case: $3,000 as intel here, $1,000 there.

Only this branch has the radio-contract advance fix, intel banked at extraction, the money section
and Books tab, and villagers' jobs in a hot zone. His write-up is kept below for its reasoning and
its measurements, the "why" behind each number.

### cghath's balance pass, 2026-10-20 (PR #14, feat/economy-balance)

The Captain's read after the first pass (below): too easy overall, but mission expenses swing it
negative fast. [economy_proposal_2026-10-20.md](economy_proposal_2026-10-20.md) measured why
and proposed five changes. The Captain delegated the call to cghath, who approved all five on
2026-10-20. They are now in the data and the code.

#### What changed, and why

| # | What | Where | Was | Now | Why |
|---|---|---|---|---|---|
| 1 | Contract pay | `data/contracts.json` `difficulty_pay` | 0, .5, .7, .9, 1.15, 1.45 | 0, .35, .5, .6, .75, .95 | Pay was about twice the running costs of the days it took. About a third off at every rating keeps the curve's shape: a 5 still pays 2.7x a 1. |
| 1 | Hot-zone rate | `hot_zone_pay_mult` | 1.4 | 1.0 | A hot deployment already hands the squad 3 to 6 contracts at once, each rated higher. It pays by volume, so it doesn't also need a better rate. Hazard pay still rewards staying. |
| 1 | Clean bonus | `clean_bonus_share` | 0.1 | 0.05 | It pays on almost every contract: it's the norm, not a feat. |
| 2 | Intel sale | `DebriefCalc.intel_price` (`Contracts.server_sell_intel`, the debrief's Sell button); new setting `intel_sale_mult` | a flat `intel_sale_price` of $6,000 | its `intel_value` x 1.0: USB drive $600, documents $800, phone $1,200, ledger $1,800, laptop $3,000, Vantage ledger $4,000 (no value: $1,000) | prices.json already said intel is worth its intel_value. $6,000 for a $600 USB drive made intel a quarter of a looting squad's income. |
| 3 | Hot-zone arrival contracts | `Contracts._hot_zone_extras` -> `server_accept(..., on_completion)` | standard terms, 30% advance on arrival, kept if they lapse | no advance, the whole pay on completion | Walking into a hot zone and straight out paid about $80k in kept advances. |
| 4 | Wages and upkeep | `Economy.advance_days` -> `pay_day` | the week's bill once a week | a seventh each day (a week's shares add up to the week's bill exactly); loan installments still weekly | Each debrief now carries its own days ("Wages and upkeep (N days)"). No single debrief takes a $45k week, so its "net after expenses" is what the job made after its own days. The weekly total is unchanged. |
| 5 | Lost helicopter | `data/prices.json` `lost_supports` | resupply 30,000, the rest 40,000 | 15,000 each (x the airframe's `lost_mult`) | An insurance deductible. A shot-down helicopter was the biggest single line a competent squad couldn't avoid. |
| 5 | Bought respawns | `respawn_rise`; new `respawn_max` (`RosterDeployment.respawn_cost`) | rise 0.5, no cap (4,000, 6,000, 8,000...) | rise 0.25, at most 8,000 (4,000, 5,000, 6,000, 7,000, 8,000...) | The rising price was the steepest curve in the game: a bad hot zone ran up $127,000 in respawns. |
| 5 | Death benefit | `operations.kia_benefit` | 15,000 | 10,000 | In step with pay a third lower. A loss still costs the benefit, a sign-on fee and the man's experience. |

The debrief's money section shows the running costs per day from now on, and any loan
installment due. The contract board and the base show the daily cost as well.

The proposal also flagged two loopholes it didn't model. Both were real, and both are fixed:

- **Intel could be sold twice.** Selling a piece or turning it in left the item with whoever
  carried it, so it could be sold again. The shop paid 40% of its price for it, and a later
  debrief listed it again if it was carried out on another deployment. Now the shop never buys
  intel (`Prices.sell_price` is 0, and selling from the stash refuses instead of taking the item
  for nothing). A piece sold or turned in is marked spent by its own `intel_id`
  (`Contracts.intel_spent`), and no later debrief lists it.
- **Hiring and releasing for kit.** A new hire brought their role's kit free, and letting them go
  put all their gear in the stash: kit worth $6,100 to $11,600 at shop prices for a sign-on fee
  of about $2,100. Now `Hiring` notes the kit it issued (`issued_kit`), and
  `BaseHub.server_release` lets them take that much with them. Only what the company added comes
  back. Members hired before this change have nothing noted, so all their gear comes back as
  before.

#### The sim after the change

`tools/economy_sim.tscn -- --runs 40 --variant current` was run on 2026-10-20 at 9e65fc0. It
plays the applied rules (its `PROPOSED` table is now empty). The table gives five in-game weeks,
40 campaigns per profile, mean cash:

| Profile | Cash at day 35 (p10 to p90) | Proposal's "proposed" | Worst deployment | Proposal | Debriefs shown negative | Proposal | Deployments negative (real result) |
|---|---|---|---|---|---|---|---|
| Careful | $406k ($313k to $496k) | $490k | -$25.6k | -$15k | 23% | 20% | 8% |
| Median | $592k ($311k to $790k) | $582k | -$74.8k | -$45k | 31% | 34% | 19% |
| Sloppy | $103k (-$46k to $400k; $47k less loans) | $125k | -$113.5k | -$99k | 71% | 68% | 66% |

Per deployment, mean economic net: careful $20.4k, median $36.3k, sloppy -$6.6k.

- Median: contract zones $12.4k, hot zones $98.1k (proposal: $12.2k and $98.9k).
- Sloppy: contract zones -$24.5k, hot zones $28.2k (proposal: -$20.1k and $30.7k).
- Arrival advances kept whatever happens: $0, against $80k a hot deployment before.
- Out of credit by day 35: sloppy 5 of 40 (proposal: 2).
- Careful income shares: contract pay 66%, bonuses 9%, loot 14%, intel 4%.

**Why careful differs from the proposal's table.** After the proposal was measured, the compound
loot rework (cb67bcf, `data/loot_tables.json`) replaced the site-box roll that the sim called. Its
old calls no longer existed, so the sim couldn't run on dev. The sim now reads the boxes through
`WorldValuables.site_plan`.

To check the change itself, dev's own code (52037f2) was run through the proposal's emulation of
these rules, with only that loot fix, on the same 40 seeds. It gave the same numbers:

- careful $405.8k at day 35, matching to the dollar;
- median $590.4k;
- sloppy $109.3k, within the sim's known ~2% to 5% run-to-run spread for the median and sloppy
  profiles.

So the code does what the proposal modelled. The gap to the proposal's table is the new loot:

- Careful's intel fell from $24.6k to $11.9k a deployment under the old rules, and to $2.2k under
  the new ones.
- On today's loot the old rules gave careful $786k, median $1,519k and sloppy $691k at day 35.
  The new rules cut that to $406k, $592k and $103k.

The worst single deployments are rare outliers, a failed rating-4 job with every shock at once.
For median, that meant $20k of supports, a lost helicopter, $15k of respawns and a death. The
10th percentile is -$12.3k (median) and +$2.8k (careful).

#### Tests

`tests/contracts_test.gd` covers these checks:

- "Daily wages and upkeep, and the safety floor": a seventh a day, seven days make the week's
  bill exactly, one debrief line, emergency loans as bills fall due, installments at the week's
  end.
- "Economy balance": 14 days are one line of two weeks' wages and upkeep, and a 2-day debrief
  carries its 2 days.
- The intel sale at its worth.
- Debrief totals with the 5% clean bonus.
- "Intel sells for its worth, once".
- "Hot-zone arrival contracts pay on completion".
- "Economy balance numbers (2026-10-20)".
- Debrief cash checks take the days' bills off.

`tests/base_test.gd` covers these checks:

- "Wages", paid daily.
- "Respawn pool": 4,000, 5,000, 6,000, 7,000, then 8,000 at most.
- "Letting a hire go".
