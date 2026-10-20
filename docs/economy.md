# Economy balance (feat/economy-balance)

Captain: "not enough expenses to balance, so it's easy to stack cash". Every number is Proposed.

## Money flow, typical contract (difficulty 3 raid, contract zone, squad of 6 out, 8 on the roster)

| | Before | After |
|---|---|---|
| Contract pay (46k base x difficulty 3, ~0.95 term) | ~$48,000 (+10% clean bonus) | ~$39,000 (+10%) (difficulty_pay 1.1 -> 0.9) |
| Days (1 + travel) | 2 | 2 |
| Wages (8 roster, per day) | ~$0.8k (WAGE_BASE 40) | ~$3.5k (WAGE_BASE 300, 150/skill, 6/mission) |
| Base upkeep (per week) | $4,000 | $21,000 |
| Field costs (ammo/meds/fuel/comms) | none | $700 per person per day = $8,400 |
| Death benefit per KIA | none | $15,000 |
| Treatment per wounded | none | $1,200 |
| Resupply / transport / AAV / extraction call | 8k / 6k / 12k / 10k | 12k / 9k / 18k / 14k |
| Helicopter lost on an op | free (support gone) | $30-40k replacement |
| Respawn past the free pool (4 contract, 8 hot) | 1,000 (+50% each) | 4,000 (+50% each) |
| Net of a standard contract | ~$44k (90%) | ~$12-22k (30-45%), nothing bought |
| Disastrous (2 KIA, lost heli, 2 supports, failed) | still positive | about -$75k |

Top gear (Javelin $15k, optics $3k, defib $2.4k) now takes a few contracts, not one.

## Where each cost lives

- Wages + upkeep: `Economy.weekly_bill()` is the week's; `Economy.pay_day()` charges a seventh of it every campaign day (`advance_days`; since 2026-10-20, see below), listed as one "Wages and upkeep (N days)" line in the next debrief's expenses. Loan installments: on the week's last day, listed as "Week N: loan installments".
- Field costs, death benefit, treatment: `DebriefCalc.expenses()`, charged in `Contracts.server_end_deployment`.
- Respawns (`BaseHub.server_count_respawn`), support calls (`Economy.server_pay_support`), lost helicopters (`HeliSupports.server_lost`): `Economy.charge_run` / `note_run_expense`; refunds are listed as negatives.
- Existing and unchanged: shop prices (gear lost in the field is bought again), repairs, motor-pool vehicle repair + fuel, medbay, hiring fee (days of the wage asked, so it rose with wages), loans.
- Debrief screen: header stats "Expenses" and "Net after expenses", a "WHERE THE MONEY WENT" section (with the running costs per day from now, and any loan installment due) and the summary lines.

## Knobs

- `data/prices.json`: `weekly_upkeep`, `default_wage_bill`, `operations.{per_head_day,kia_benefit,wounded_care}`, `supports`, `lost_supports`, `respawn`, `respawn_rise`, `respawn_max`.
- `scripts/campaign/roster.gd`: `WAGE_BASE`, `WAGE_PER_SKILL`, `WAGE_PER_MISSION`.
- `data/contracts.json` settings: `difficulty_pay`, `hot_zone_pay_mult`, `clean_bonus_share`, `intel_sale_mult`.
- Tests: `tests/contracts_test.gd` "Economy balance" (standard contract nets 10-60%, disaster negative, a debrief's days of wages and upkeep as one line, respawn cost), "Daily wages and upkeep, and the safety floor", "Intel sells for its worth, once", "Hot-zone arrival contracts pay on completion", "Economy balance numbers (2026-10-20)"; `tests/base_test.gd` "Wages", "Respawn pool", "Letting a hire go".
- The balance sim: `tools/economy_sim.tscn` (not a test suite; see the proposal for how to run it).
