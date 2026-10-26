# Contractor: Fallen: the survivor's hands, spoilage and the clinic

The player's side of nature (calls 42, 100-107: the nature lane built the simulation and left the
menus), food going off (calls 23-26, 96) and the settlement's clinic (calls 60-63,
docs/survival_medical.md sections 1-3). Built on `claude/survival-hands`. Every number is **Proposed**
(consts at the top of each file).

## Where the build is

- 2026-10-26: fieldwork, spoilage and the clinic built; the `hands` suite. **R2697 PASS** (hands, survival, nature, body, settlement).

## Fieldwork (`Fieldwork`, scripts/survival/fieldwork.gd)

What you look at decides the contextual menu (`ContextMenu.classify` asks `Fieldwork.classify` first in
a survival zone; `ContextResolver` lists `Fieldwork.options`; the one key does the first). The host
does the work (`Survival._server_fieldwork` -> `Fieldwork.server_request`) as timed jobs with the hands
busy (`Wear.timed`).

| Looking at (within 4 m) | Entries | Rules |
|---|---|---|
| A carcass | Butcher the deer | A blade. `butcher_s` from the fauna data (deer 40 s, boar 35, bear 90, rabbit 10); fieldcraft takes 6% a level off (to half) and adds 10% a level to the meat. Heard 15 m. Meat, hide, bones, fat. |
| A tree | Fell the oak, Gather firewood, Pick apples | Felling is `Trees.server_fell` a chop (2 s) at a time, each heard; walking off stops it. Planks and green firewood. Deadfall: no tool, 30 s, 1-2 dry firewood, 2 gathers a day a 25 m patch. |
| A plant | Forage Wild Berries / Forage (unknown plant) | Known when his eye (fieldcraft, a field guide +2) reaches the plant's tell, or the tell of a poison that looks like it (a novice can't tell berries from nightshade either way). 4 s, then `Foraging.server_forage`. |
| Water (within 14 m) | Fish; Cut ice, Fish through the ice | A rod (1), a net (2.5), a hand line (0.6). A cast is 20 s standing for half an hour of the nature lane's fish table: bite chance 1 - e^(-rate x gear x fieldcraft x 0.5); through the ice x0.3. Ice: 15 s, 2 blocks. |
| The woods (a tree within 12 m) | Set a snare, Check the snare, Gather firewood | Snares catch by the species' `snare_h` an hour (rabbit 6%, raccoon 1%), fieldcraft +15% a level. |

Pieces (`BuildPiece`'s menu -> `Fieldwork.piece_menu`, `Builder` piece_act -> `server_piece_act`):
**fish trap** (in water: a catch an hour at 0.3 a rod's rate, up to 4; "Empty the fish trap"),
**smoker** and **drying rack** (recipe stations: `stations_near`; "Smoke the meat and fish you carry",
"Hang meat and fish to dry"), **cold store**, **ice box**, and the clinic's pieces.

New recipes: wire snares, a hand line, salt meat/fish (hands), smoker meat/fish (3 and a firewood),
dry meat/fish on the rack.

## Spoilage (`Spoilage`, scripts/survival/spoilage.gd)

- A perishable (food, `spoils_days` at most 100) carries `fresh_until` (a world hour) and `stage` in its
  state. Made now (butchered, caught, picked, crafted, or anything new to a kit unstamped) it is fresh
  for 60% of its life, stale (shown "going off") for the rest, then spoiled. Same-hour stamps stack
  (`Inventory._state_stacks` lets perishables stack on equal state).
- Found food: `Spoilage.found_state(id, where_at(world, pos))`: a powered fridge 100% of its life left,
  indoors 30-70%, outdoors 0-40%. No loot table holds perishables yet, so nothing calls it.
- Pace: the season (`Seasons.spoil_mult`: summer x2, winter x0.5); the larder: a cold store x0.5, an
  ice box x0.25 (ice in stock, or winter; a block melts every 2 days a box out of winter), a powered
  fridge stops it. The host steps stamps by whole world hours (`Fieldwork.server_tick` for kits,
  `Settlement.server_hour` for the larder).
- Eating (`Needs.eat`): stale half the food values, spoiled a quarter; food poisoning (Needs'
  sickness) 5% stale, 60% spoiled.
- The larder throws spoiled stock out (counted in the settlement's "larder" lost, a journal line a
  day) and keeps each store oldest first, so the cook and the meals use the oldest first.
- Shelf lives: salted meat 60 days, salted fish 45, dried meat 45, dried fish 30, smoked meat 30.

## The clinic (`Clinic`, scripts/survival/clinic.gd)

- Pieces: `clinic_bed`, `clinic_cabinet`, `clinic_lamp` (counted in the settlement record).
- **In care**: a player lying within 2.5 m of a built clinic bed (Surgery's "clinic" surface): wounds
  heal x1.5 (x2 with a doctor at the settlement), sicknesses run out x1.5, the clean bed takes dirt off
  open wounds, a doctor's care slows the bite's fever (BiteFever's `care_h`). The body screen shows
  "in care: <doctor>".
- **The doctor** (job "doctor"): a settler with medicine 2 (skills or background) and a clinic bed.
  An hour: the quarantined, then the wounded and the sick, into the beds (one each); up to 2 wounds
  treated, a med from the cabinet each; a gunshot wound operated on first (60% +8% a level over 2,
  x0.7 without a med; infection 6% halved).
- **Surgery in a clinic**: after a good operation a post-op roll leaves the wound contaminated: clinic
  6% (3% with a doctor), a bunk or table 15%, a floor 20%, the ground 30%. A test that forces Surgery's
  own roll skips it (`Clinic.post_op_roll`).
- **The cabinet**: the settlement record's `clinic.stock`; "Stock the cabinet with your meds" from its
  menu; under 2 the doctor files a "medical supplies" work order (6), which a doctor fills from the
  stores' meds.
- **Quarantine**: `Clinic.server_quarantine(rec)` (or "Quarantine the bitten here" on a clinic bed):
  the flag, a bed first, and a council vote: keep them in the bed, or send them away (unsettled).

## Hooks in shared files

`ContextMenu.classify` / `run` ("fieldwork"), `ContextResolver.resolve` (the five kinds),
`Survival._server_fieldwork` (new RPC) and `server_tick_survivors` (`Fieldwork.server_tick`),
`Needs.eat` (nutrition and the sickness), `InventoryScreen._condition` (the freshness word),
`Inventory._state_stacks` (perishables stack), `Crafting._finish` (stamp) and `stations_of`,
`Wildlife.server_butcher` (bones, fat, yield; `butcher_problem`), `_give` (stamps),
`server_snare_hours` (species), `Settlement.refresh` (piece counts) and `server_hour` (the larder),
`SettlementJobs` (the doctor), `WorkOrders` ("medical_supplies"), `Body.server_step` (care),
`BodyScreen.summary`, `Surgery.server_operate` (post-op roll), `BuildPiece.interaction_actions`,
`Builder` piece_act, `BuildPieces` (8 pieces), data (items, prices, recipes, fauna).

## Left out

- Companions told "Butcher that" / "Forage here": the talk/order menus belong to another lane and have
  no order hook for jobs.
- No food is found in the world yet (loot tables hold none), so the found roll is an API only.
- Food lying on the ground or in containers doesn't go off (only kits and the larder step).
- Milk (no livestock yet), a cooked-meal recipe by hand, tanning hides, bone tools.
- Settlers' own bodies don't run Infection (their wounds are a simple list): the doctor removes them.
- The smoker as a settlement job station (the smoke-meat order still uses the stove).
- Tracking marks on the ground, a drawn snare or fish trap model (the pieces use the generic looks).
