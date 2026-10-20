# Executive audit — October 19, 2026

The two-part audit examines local `dev` at `68a1b8336013a8170b22d2a4b66e15a626feb84b`,
following the previous audit's `c39c36d` completion. Production code is unchanged.

**13 confirmed code findings: five high priority (P1), eight normal priority (P2).**
The current checkout also fails linked-zone, formation, full vehicle co-op and town-performance
checks. Those validation failures are described separately from diagnosed root causes.

## Fix first

| Priority | Finding | Impact |
| --- | --- | --- |
| P1 | A2-01 | A raid can activate a prepared contract from another zone. |
| P1 | A2-02 | Saves omit current helicopter losses/cooldowns. |
| P1 | A2-03 | Returning to a zone can leave scenario objectives permanently without a controller. |
| P1 | A2-09 | Taking over a casualty's HX-1 while wearing an LX-3 deletes the HX-1. |
| P1 | A2-12 | A carer boarding a vehicle can leave a stale claim that blocks backup care. |

## Other confirmed findings

| Priority | Finding | Impact |
| --- | --- | --- |
| P2 | A2-04 | Debrief/board day advances skip assault booking and rebel-week rules. |
| P2 | A2-05 | Final fighter upgrade supplies eight men instead of ten. |
| P2 | A2-06 | Rebel followers return as regular allied troops after crossing. |
| P2 | A2-07 | Raid extraction does not bank deposited loot/body equipment. |
| P2 | A2-08 | A remembered zone overrides incoming travel time with its old clock. |
| P2 | A2-10 | Independent elements do not receive their distant boarding movement order. |
| P2 | A2-11 | AI belt handoffs discard remaining-round state and can create ammunition. |
| P2 | A2-13 | Optional aim slowdown targets civilians and enemies behind solid walls. |

See [Part 1: campaign, saves and travel](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/executive-2026-10-19/PART-1.md>)
and [Part 2: combat, AI, co-op, performance and tooling](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/executive-2026-10-19/PART-2.md>)
for triggers, source locations, reproductions, suggested corrections and validation limits.

Recommended sequence: fix the five P1 issues, then the remaining code findings; resolve the
failed integration/performance gates before treating a build as validated. Repairs should
retain meaningful negative regressions for the reproduced cases.

This work is an audit. No production fixes, push, merge, export or publication were performed.

Subsequent local repairs and their validation are tracked in [FIXES.md](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/executive-2026-10-19/FIXES.md>).
