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
| Hot zone pay rate (`hot_zone_pay_mult`) | x1.4 | x1.0 | A hot zone already hands out 3-6 contracts, each rated higher. |
| A hot zone's arrival and radio contracts | 30% advance up front, kept if they lapse | nothing up front, all on completion | Walking in and straight out kept about $80,000. Radioing for contract after contract kept 30% of each. |
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
- **Advance farming in hot zones** (see the table: arrival and radio contracts).

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
- Field costs, death benefit, treatment: `DebriefCalc.expenses()`, charged in `Contracts.server_end_deployment`.
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
