# Contractor: Fallen — trade and the intel layer (phase C)

Lane `claude/survival-intel`. Design: survival_world.md sections 8 (trade) and 10 (information);
calls 26, 37, 45, 54, 95, 98. Suite: `intel` (tests/intel_test.gd).

## What's built

- **The value scale** (`WorldTrade.value`, world_trade.gd): data/prices.json's item price, else its
  tags, else its type's default; then the survival weights by `Settlement.category_of`: a
  category floor (a $3 tin is at least $15 of food) times a weight (ammo, meds, food, fuel x2,
  water x1.5, parts x1.2); season and region multipliers are hooks (`SEASON_MULT`, `REGION_MULT`,
  `WorldTrade.season`). Cash (`SurvivorPerson.CASH_VALUE`: roll $50, bundle $250, brick $2500) is
  worth its face, drifting +-15% by the world's seed.
- **Traders' prices** (`WorldTrade.buy_price` / `sell_price`): the value x the group's need (lacks
  that supply x1.5, has it spare x0.75) x its standing (at 0: pays 85%, asks 115%; each 100
  standing moves both 20% your way). Cash is never marked up.
- **Barter** (barter.gd): who trades (a settlement's leader or a "trader" role, scavengers,
  lone survivors from their kit, the enclave's quartermaster: rec "role" or the enclave lane's
  `Enclave.is_quartermaster(rec)` by has_method; raiders, cultists and groups at -40 or worse
  don't); their stock (their kit, their group's spare supplies as items: canned meat, water,
  jerrycans, 9 mm rounds, bandages, scrap, planks, up to 8 each, and the group's cash); the deal;
  `server_trade` (refused unless it favours them or is even; your goods go into their group's
  supplies or cash or their kit, theirs into your inventory and the rest at your feet; standing
  up through `WorldSim.server_player_trade`; a "trade" event; a journal line); `server_cheated`
  (-30 with the group, -10 with every group in its zone or the next or that knows it; a
  "cheated" event).
- **TradeScreen** (trade_screen.gd, on the HUD): two columns with per-item prices, +/- to put
  items on the table, a running balance, Confirm when even or in their favour. Opened by the
  talk menu's **Trade** on a trader (the host sends the deal: `Intel.server_send_deal`).
- **Rumours in the talk menu**: **Ask about...** (What happened here?, Other places, The groups
  out there, The enclave) on anyone, including the world sim's live people (WorldLive bodies now
  carry metas `world_person` / `world_group` and talk: Who are you, Ask about, Trade).
  `Intel.server_ask` tells the next untold rumour on the topic (`WorldSim.rumours_for`): a journal
  entry ("told", by the teller) and, naming a zone, the zone on the map as told and a mark there
  (kind "told", `teller`). Whether it was true, half-true or a lie is never recorded.
- **Companions report** (`Intel.server_report_tick`): once a world hour, a companion tells the
  newest event near the players nobody reported yet (a journal line, said aloud).
- **The journal** (journal_screen.gd, key **7**): tabs Log (by day), People (met: want, skills,
  group, where last seen), Places (marks: age, who told, faded), Deadlines (demands' hours left;
  `state()["deadlines"]` for other lanes' clocks, a fever clock among them), The trail
  (`state()["trail"]`, the enclave lane's), and the radio's switch.
- **The radio** (radio.gd, `FallenRadio`): the "radio" item is dead until repaired (one
  radio_parts and mechanics 2 via `Rpg.gate`); power from batteries (battery_aa / cr123, 12 h
  each) or standing at the settlement while its generator runs. On: a broadcast every 2 world
  hours, in turn: group chatter (the newest event within range: hills and desert 3 links, plains
  and coast 2, city 1), the enclave (events of kind "broadcast", else its evac call), ARCHE's
  numbers station (`state()["trail"]["numbers"]`, else canned lines). Each a journal line
  ("radio"), a mark when it names a place, a HUD message.
- **The map** (fallen_map.gd): marks show who told them; each known zone washed faintly in the
  colour of the group holding most of its region (`FallenMap.political_colour`, from
  `WorldSim.region_holders`); landmarks drawn at the zone zoom; standing at a **map table** adds
  the reports (red crosses, dashed trade routes, aged group dots, a list top left).
- **Landmarks** (landmarks.gd): each zone's modules named ("the church", "the north farm") plus
  two seeded tall things (water tower, radio mast, a named hill); `Landmarks.nearest_name(pos)`,
  `meet_order(pos)` ("Meet at the water tower"), `resolve(name)` back to a point.
- **The map table** (map_table.gd, build piece `map_table`): sightings of the last day by groups
  at standing 50+, trade events of the last 3 days between homes, known movements (allies'
  scouting and what we were told) for 7 days, aged.

## Defaults (all Proposed)

Weights and floors above; NEED_HIGH 1.5 / NEED_LOW 0.75; BUY_AT 0.85 / SELL_AT 1.15 / REL_X 0.2;
cash drift 15%; stock cap 8; group cash 400 settlers / 600 scavengers / 3000 enclave; cheat -30 /
-10 heard; hostile -40; journal key 7; radio repair mechanics 2, one battery 12 h, a broadcast every
2 h; report once an hour; map table reach 3 m, sightings 1 day, routes 3 days, movements 7 days;
political wash alpha 0.16; 2 seeded landmarks a zone.

## What's left

- No steal action exists: `Barter.server_cheated(gid)` is the hook for it.
- Companions don't yet take landmark orders (the API and the order string are there).
- The map table's reports draw on the host's map only (a peer's map gets them with a later sync).
- Found maps and notes adding to the map; the radio as an inventory action (it's in the journal).
- Seasons (phase D) to fill `WorldTrade.season`; cash drift over time (now per seed only).
