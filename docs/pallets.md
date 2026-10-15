# Supply pallets, tagging and the FOB's stocks

Captain's design, 2026-10-15. Every number is Proposed and lives in `data/pallets.json`.
Code: `scripts/campaign/pallets.gd` (data, lots, offsets), `scripts/world/pallet_field.gd` and
`scripts/world/supply_pallet.gd` (the field), the FOB stocks in `Economy` ("FOB stocks" section),
the debrief rows in `scripts/ui/debrief.gd`, the Supply cage page in `scripts/campaign/base_ui.gd`.
Test: `tests/pallets_test.gd` (suite `pallets`).

## In the field

Enemy sites carry **pallets**, not loose items: fuel drums, fuel bladder, general supplies, ammunition,
spare parts, medical, and mixed loads. A pallet holds stock units of one or more stock kinds (fuel, ammo,
parts, supplies, medical); each pallet's amounts are the kind's contents scaled 0.7 to 1.3 by a hash of its
uid (same on every peer), so values vary (a fuel-drum pallet is about $1,000, a mixed load about $2,900).
Sites (module-local coordinates, `sites` in the file): outpost 2, checkpoint 2, village 2, QRF base 3,
HQ 4, comms 1. A site can also park an **abandoned vehicle** (`site_vehicles`: a technical at the checkpoint
and at the QRF base, hostile faction, nobody aboard, `no_save`); wrecks and captured vehicles tag the same way.

Hold Left Ctrl at a pallet (or at a hostile/abandoned vehicle's door or service point):

- **Tag to sell**
- **Tag for...** (a submenu of the employers: gift to a faction you favour)
- **Untag** (when tagged), **Check pallet** (contents and value).

The host decides every tag (`PalletField.server_tag`: real target, within `reach_m` 7 m, 11 m for a vehicle, valid
faction, nobody aboard a vehicle), tells every peer (`_apply`), sends a joiner all tags, and puts a map marker
("Sell: Fuel drums", "Gift Meridian: Ammunition crates") on the shared map (`MapMarkers`, colour orange or green).
A tagged pallet shows a floating label (`TAG: SELL`, `GIFT: <faction>`).

## After extraction: the debrief

`Contracts.report_from_level` adds `"tagged"` (every tagged pallet and vehicle still there; nobody carries them,
they are hauled home with the squad); `server_end_deployment` puts them in the debrief as `debrief.tagged` lots
(`{uid, kind, what, label, units, value, tag, faction, status}`). The debrief screen lists them, each with:

| Option | Effect |
| --- | --- |
| **Sell now** | `sell_now_ratio` 0.5 of the value, cash at once (quick, lower price) |
| **Store** | into FOB storage (`Economy.pallet_store`), sell/gift/keep later |
| **Keep for FOB** | the units go into the FOB's stocks (pallets only; a vehicle can't be kept yet) |
| **Gift** | reputation with the chosen faction: value / `gift_rep_per` (600), 1 to `gift_rep_max` (8) |

Anything undecided when the debrief closes: a lot tagged **for a faction** is gifted to it, the rest goes to
storage (`Contracts._settle_tagged`). Requests are `pallet` and `draw` in `Contracts` (server-authoritative,
malformed ones refused like the others).

## At the FOB

The **Supply cage** (a terminal at the base, page "stores") shows the stocks, the lots in storage and the
actions on them. Selling from storage pays `sell_stored_ratio` 0.8 (patience is worth a little). Stocks and
storage are part of Economy's section: saved with the campaign, copied to every peer.

What stock does (`stock_effects`; each kind covers a share of a cost at `offset_per_unit` per unit and only
as many units as that takes are used up):

- **Fuel** covers part of support calls that fly or drive (transport, extraction 30%, AAV 25%).
- **Parts** cover up to 60% of a repair (`Economy.server_repair`) and 10% of an AAV call.
- **Ammo, supplies, medical** cover part of a resupply call (40/20/20%) and can be **drawn into the armory
  stash** (`Pallets.server_draw`: a unit of ammo is 4 magazines, supplies a smoke grenade and 2 zip cuffs,
  medical an IFAK; they arrive in the base inbox like bought gear).
- Support calls are paid in `Economy.server_pay_support` from the contract's support budget first, then the
  stocks offset the remainder, then cash.

## Hook for feat/economy-balance (field costs, repairs, resupply)

`Pallets.offset_preview(amount, "field_costs")` already answers how much the stocks would cover of a charge
(`field_costs` shares in the file: fuel 25%, ammo 25%, supplies 15%, medical 15%) and
`Pallets.take_stock(used)` uses them up. After that branch merges, in `DebriefCalc.expenses`' field-costs line
(or where `Contracts.server_end_deployment` charges `spent.charge`): take the preview of the field-costs line, charge
`amount - offset`, call `take_stock`, and list "Covered by FOB stocks: -$N" as its own line in "WHERE THE MONEY
WENT". Repairs and support calls are already wired (above); `note_run_expense` there should record the amount
after the offset.

## Later: the sale mission (a hook only, not built)

A fourth way to sell: convoy the goods to a **fixer** at a meeting point. `Pallets.sale_offer(lot, fixer)` is the
stand-in: it returns `{available: false, price (value x sale_mission.price_ratio 1.1, above the storage price),
betrayal_risk}`, where the risk rises as reputation with the fixer falls below `betrayal_rep` (10), capped by
`betrayal_max` (0.6): a low-rep fixer may rob the convoy at the meeting. The mission would take lots out of
storage (`Economy.server_unstore_lot`) and put them on a vehicle or pallet convoy in a contract zone.

## Knobs (data/pallets.json)

`stock_kinds` (unit_value for sale, offset_per_unit for costs), `kinds` (contents, colour), `variance`,
`sell_now_ratio`, `sell_stored_ratio`, `gift_rep_per`, `gift_rep_max`, `reach_m`, `vehicle_values`, `wreck_ratio`,
`sites`, `site_vehicles`, `stock_effects` (`support`, `repair`, `field_costs`), `draw`, `sale_mission`.
A zone definition with `"no_pallets": true` has none.
