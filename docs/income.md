# Income: making money with the flow of the game

Captain, 2026-10-22: "we need something that allows the players to make money", "like **good
money** but it needs to **go with the flow of the game**". So every stream here comes out of
something the company already does (contracts, the living war, high command, fixers, salvage, the
FOB) and feeds back into it. None of it is an idle menu that pays for waiting.

Code: `Income` (scripts/campaign/income.gd: the section, zone danger, the daily tick, requests)
and one class per stream. Numbers: data/income.json, **all Proposed**. UI: the base screen's
**Side work** page (scripts/ui/side_work_page.gd) and a summary on the contract board (button
**Side work [J]**). Tests: `tests/income_test.gd` (suite `income`).

| # | Stream | Class | Status |
|---|---|---|---|
| 1 | High command squads' side jobs | `SideJobs` | Built |
| 2 | Captures and bounties | `Bounties` | Next |
| 3 | FOB businesses | `FobBusiness` | To do |
| 4 | Black market trading | `BlackMarket` | To do |

## Shared pieces

- **Zone danger** (`Income.zone_danger`, 0..1, data `danger`) is read from the living war:
  - held by the company or the rebels: 0.12;
  - held by an employer that deals with the company: 0.22;
  - held by anyone else: 0.45 + their war strength / 250;
  - a front there: +0.25;
  - a firm friendly hold calms it a little.
  The screen shows it as Low / Moderate / High / Severe.
- **The daily tick:** `Income.server_advance_days`, called from `Economy.advance_days` right after
  the war's own tick. So resting, a deployment's days, and the board's Wait buttons all move it
  the same way.
- **Requests:** `BaseHub.request("income", [op, ...])`. Any peer can ask, from anywhere (the base
  or the field). `Income.server_request` decides; sending squads is the host's call.
- **Sync:** the "income" section rides on `Economy._public()`, so every peer's Side work page
  shows the host's state.
- **Books:** each stream's ledger lines start with their own prefix, and `Economy.ledger_kind`
  sorts them ("Side job" → "Side jobs").
- **Reports:** `Income.report` posts a line on the company net (a notice to every peer) and adds a
  debrief card on the Side work page (the last 12 are kept).

## 1. High command squads' side jobs

Between contracts, or during one (a squad left at home), the host sends Hawk 2 or Viper 3 on a job
of its own. Hero squads, once there are more detachments, work the same way.

**Where offers come from.** Every day the board tops up to 3 side-job offers. They come from:
- the kind's client factions that deal with the company (Neutral or better, not barred from work);
- the fixers (Halloran for Meridian, Mama Rook for the Salvage Union) once the company is at their
  `min_rep`, at the fixer's `pay_mult`.

Each offer is in one of the war's zones and lasts 4 days. Its danger and pay follow the war every
day until a squad takes it.

| Kind | Days | Base pay | Risk | Clients | Extra |
|---|---|---|---|---|---|
| Escort a client | 2 | $26,000 | 0.40 | Meridian, Vessmark, US, UK, CA, Salvage Union | |
| Guard a site | 3 | $30,000 | 0.30 | Meridian, Salvage Union, Vessmark, US | |
| Train locals | 4 | $22,000 | 0.15 | Vessmark, UK, CA, US | +4 rebel support in the region on success |
| Run a supply route | 2 | $20,000 | 0.35 | Salvage Union, Meridian, Vessmark | |
| Recover a vehicle | 2 | (the vehicle's sale) | 0.45 | (from item 2) | brings a captured vehicle out to a buyer |

**Pay** = base pay × (0.6 + danger × 1.3) × the client's pay rate for the company's standing
× the fixer's rate. A quarter comes up front and is kept whatever happens. The rest comes when the
squad comes back with the job done.

**The squad's quality** (0..1) is made of:
- 35%: the mean skill of its fit men;
- 25%: their kit (what their gear is worth against a fully kitted man, $9,000);
- 25%: morale;
- 15%: men fit out of four;
- ±5%: the leader's leadership.

**Morale** is new and saved per squad:
- it starts at 0.7;
- +0.05 for a job done, −0.1 for a failed one, −0.15 for each man lost;
- it drifts back toward 0.7 by 0.02 a day while the squad is home.

**The roll.** Off-screen, seeded per campaign and job, so it comes out the same every time:
- trouble = risk × (0.5 + danger) × (1.45 − quality), clamped to 4-85%;
- in trouble, one or two men are wounded (3-9 days);
- a 30% share of troubled jobs lose a man;
- a 35% share fail outright (no pay beyond the advance, −1 standing with the client).

The page shows each squad's trouble, loss and fail odds on its Send button before anything is
committed.

**While it's away**, the squad doesn't deploy (`Heroes.deploying` skips it). The page shows where
it is and when it's back.

**When it's back**, the squad reports on the company net, a debrief card shows the pay and who was
hurt or killed, and every man's history gets a line.
- A man killed goes on the memorial wall with his tags (his squad brought him home), and his death
  benefit is paid.
- The wounded sit out in the medbay as usual.

**Why it goes with the flow:**
- the squads are the company's own and cost wages anyway;
- the danger comes from the living war;
- training locals raises rebel support;
- a squad out on a job is a squad not beside you on the next contract;
- losses come out of the same roster, wall and benefits as the main game.

## Before and after (sim)

To come after all four streams are in: the 40-campaign sim (tools/economy_sim.gd) re-run with
them, and tuned.
